/* HyperOS FCM Unified Guard: minimal kernel alarmtimer sleep helper.
 * SPDX-License-Identifier: MIT
 * No libc dependency; AArch64 Linux syscall ABI, static PIE-free ELF.
 * Usage: fcmu_alarm_wait SECONDS
 * CLOCK_BOOTTIME_ALARM (9) wakes an idle device at the specified deadline.
 * Returns nonzero if the kernel has no alarmtimer support or CAP_WAKE_ALARM.
 */
typedef unsigned long u64;
struct ts { long sec; long nsec; };
struct its { struct ts interval; struct ts value; };
static inline long call1(long n,long a){register long x8 asm("x8")=n;register long x0 asm("x0")=a;asm volatile("svc #0":"+r"(x0):"r"(x8):"memory");return x0;}
static inline long call3(long n,long a,long b,long c){register long x8 asm("x8")=n;register long x0 asm("x0")=a;register long x1 asm("x1")=b;register long x2 asm("x2")=c;asm volatile("svc #0":"+r"(x0):"r"(x1),"r"(x2),"r"(x8):"memory");return x0;}
static inline long call4(long n,long a,long b,long c,long d){register long x8 asm("x8")=n;register long x0 asm("x0")=a;register long x1 asm("x1")=b;register long x2 asm("x2")=c;register long x3 asm("x3")=d;asm volatile("svc #0":"+r"(x0):"r"(x1),"r"(x2),"r"(x3),"r"(x8):"memory");return x0;}
static int run(long *stack){
 long argc=stack[0];char **argv=(char**)(stack+1); long sec=0;
 if(argc!=2)return 2;
 for(char *p=argv[1];*p;p++){if(*p<'0'||*p>'9')return 2;sec=sec*10+(*p-'0');if(sec>3600)return 2;}
 if(sec<1)return 2;
 long fd=call1(85,9); /* timerfd_create CLOCK_BOOTTIME_ALARM */
 if(fd<0)return 3;
 struct its when={{0,0},{sec,0}};
 long result=call4(86,fd,0,(long)&when,0);
 if(result<0){call1(57,fd);return 4;}
 u64 count=0;
 long n=call3(63,fd,(long)&count,sizeof(count));
 call1(57,fd);
 return n==8&&count>0 ? 0 : 5;
}
__asm__(".global _start\n_start:\nmov x0,sp\nbl fcmu_entry\n");
__attribute__((used)) void fcmu_entry(long *stack){int rc=run(stack);call1(93,rc);for(;;){} }
