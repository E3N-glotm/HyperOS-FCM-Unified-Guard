#define _GNU_SOURCE
#include <arpa/inet.h>
#include <errno.h>
#include <inttypes.h>
#include <linux/tcp.h>
#include <netinet/in.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <unistd.h>

/* No ptrace attach, no global sysctls, no packets sent by this helper. */
#ifndef __NR_pidfd_open
#define __NR_pidfd_open 434
#endif
#ifndef __NR_pidfd_getfd
#define __NR_pidfd_getfd 438
#endif

static int read_option(int fd, int level, int option, int *value) {
    socklen_t n = sizeof(*value);
    return getsockopt(fd, level, option, value, &n);
}
static int set_option(int fd, int level, int option, int value) {
    return setsockopt(fd, level, option, &value, sizeof(value));
}
static int fail(const char *operation) {
    fprintf(stderr, "%s: %s\n", operation, strerror(errno));
    return 1;
}
static int identity(int pid, unsigned uid) {
    char path[64], name[128] = {0}, line[256];
    snprintf(path, sizeof(path), "/proc/%d/cmdline", pid);
    FILE *f = fopen(path, "r");
    if (!f) return 0;
    size_t n = fread(name, 1, sizeof(name)-1, f);
    fclose(f);
    if (!n || (strcmp(name, "com.google.android.gms") &&
               strcmp(name, "com.google.android.gms.persistent"))) return 0;
    snprintf(path, sizeof(path), "/proc/%d/status", pid);
    f = fopen(path, "r");
    if (!f) return 0;
    unsigned real = 0, effective = 0;
    int ok = 0;
    while (fgets(line, sizeof(line), f)) {
        if (sscanf(line, "Uid: %u %u", &real, &effective) == 2) {
            ok = real == uid && effective == uid && uid >= 10000;
            break;
        }
    }
    fclose(f);
    return ok;
}
int main(int argc, char **argv) {
    if (argc != 8 || (strcmp(argv[1], "inspect") && strcmp(argv[1], "apply"))) {
        fprintf(stderr, "usage: %s inspect|apply PID FD UID INODE IP PORT\n", argv[0]);
        return 2;
    }
    int pid = atoi(argv[2]), source_fd = atoi(argv[3]), port = atoi(argv[7]);
    unsigned uid = (unsigned)strtoul(argv[4], NULL, 10);
    uint64_t inode = strtoull(argv[5], NULL, 10);
    if (pid <= 1 || source_fd < 0 || !inode || port < 5228 || port > 5230) return 2;
    int pidfd = syscall(__NR_pidfd_open, pid, 0);
    if (pidfd < 0) return fail("pidfd_open");
    if (!identity(pid, uid)) { close(pidfd); return 3; }
    int fd = syscall(__NR_pidfd_getfd, pidfd, source_fd, 0);
    if (fd < 0) { close(pidfd); return fail("pidfd_getfd"); }
    close(pidfd);
    struct stat st;
    struct sockaddr_storage peer;
    socklen_t len = sizeof(peer);
    int type, protocol;
    char address[INET6_ADDRSTRLEN];
    unsigned char requested[16], actual[16];
    int family, actual_port;
    if (fstat(fd, &st) || !S_ISSOCK(st.st_mode) || (uint64_t)st.st_ino != inode ||
        st.st_uid != uid || read_option(fd, SOL_SOCKET, SO_TYPE, &type) ||
        type != SOCK_STREAM || read_option(fd, SOL_SOCKET, SO_PROTOCOL, &protocol) ||
        protocol != IPPROTO_TCP || getpeername(fd, (struct sockaddr *)&peer, &len)) {
        close(fd); return 3;
    }
    if (peer.ss_family == AF_INET) {
        struct sockaddr_in *s = (struct sockaddr_in *)&peer;
        family = AF_INET; actual_port = ntohs(s->sin_port);
        memcpy(actual, &s->sin_addr, 4);
    } else if (peer.ss_family == AF_INET6) {
        struct sockaddr_in6 *s = (struct sockaddr_in6 *)&peer;
        actual_port = ntohs(s->sin6_port);
        if (IN6_IS_ADDR_V4MAPPED(&s->sin6_addr)) {
            family = AF_INET; memcpy(actual, s->sin6_addr.s6_addr+12, 4);
        } else {
            family = AF_INET6; memcpy(actual, &s->sin6_addr, 16);
        }
    } else { close(fd); return 3; }
    if (actual_port != port || inet_pton(family, argv[6], requested) != 1 ||
        memcmp(actual, requested, family == AF_INET ? 4 : 16)) { close(fd); return 3; }
    if (!inet_ntop(family, actual, address, sizeof(address))) { close(fd); return 3; }
    int levels[] = {SOL_SOCKET, IPPROTO_TCP, IPPROTO_TCP, IPPROTO_TCP};
    int options[] = {SO_KEEPALIVE, TCP_KEEPIDLE, TCP_KEEPINTVL, TCP_KEEPCNT};
    int old[4], current[4], target[] = {1, 180, 30, 4};
    for (int i=0;i<4;i++) {
        if (read_option(fd, levels[i], options[i], &old[i])) { close(fd); return fail("getsockopt"); }
        /* Never weaken an existing stricter policy. */
        if (i && old[0] && old[i] > 0 && old[i] < target[i]) target[i] = old[i];
    }
    struct tcp_info info;
    socklen_t ilen = sizeof(info);
    if (getsockopt(fd, IPPROTO_TCP, TCP_INFO, &info, &ilen) || info.tcpi_state != 1) {
        close(fd); return 3;
    }
    if (!strcmp(argv[1], "apply")) {
        /* Set the timings before enabling keepalive. */
        for (int j=1;j<=4;j++) {
            int i=j%4;
            if (old[i] != target[i] && set_option(fd, levels[i], options[i], target[i])) {
                int saved=errno;
                for (int k=0;k<4;k++) set_option(fd, levels[k], options[k], old[k]);
                close(fd); errno=saved; return fail("setsockopt");
            }
        }
    }
    for (int i=0;i<4;i++) {
        if (read_option(fd, levels[i], options[i], &current[i]) ||
            (!strcmp(argv[1], "apply") && current[i] != target[i])) {
            if (!strcmp(argv[1], "apply"))
                for(int k=0;k<4;k++) set_option(fd, levels[k], options[k], old[k]);
            close(fd); return fail("verification");
        }
    }
    printf("mode=%s inode=%" PRIu64 " peer=%s:%d keepalive=%d idle=%d interval=%d probes=%d last_data_recv_ms=%u\n",
        argv[1], inode, address, port, current[0], current[1], current[2], current[3], info.tcpi_last_data_recv);
    close(fd);
    return 0;
}
