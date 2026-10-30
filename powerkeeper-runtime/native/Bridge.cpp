#include "ArtSymbols.hpp"
#include <zygisk.hpp>
#include <lsplant.hpp>
#include <dobby.h>
#include <android/log.h>
#include <fcntl.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <unistd.h>
#include <jni.h>
#include <algorithm>
#include <cstring>
#include <memory>
#include <string>
#include <string_view>
#include <vector>

namespace {
constexpr const char* kTag="FCMU-PK";
std::vector<std::uint8_t> dex;
std::vector<std::string> detected;
std::unique_ptr<ArtSymbols> symbols;
bool art_ready=false;

void msg(int level,const char* message){__android_log_write(level,kTag,message);}
#ifdef FCMU_PK_EXPERIMENT_DIAGNOSTICS
// One-shot diagnostic transport through the official Zygisk root Companion.
// The child keeps a socket across specialize, never opens /data/adb itself.
// A root-side Companion writes bounded data; no separate polling service.
void stage_trace(int fd,const char* step) {
    if(fd<0 || !step)return;
    constexpr std::size_t limit=160;
    std::size_t length=strnlen(step,limit);
    if(length==0 || length>=limit)return;
    // Avoid SIGPIPE if a Companion is unavailable or the socket closes early.
    (void)send(fd,step,length,MSG_NOSIGNAL);
    (void)send(fd,"\n",1,MSG_NOSIGNAL);
}
void companion_trace(int client) {
    constexpr char path[]="/data/adb/fcmu_pk_experiment/zygisk-stage.tsv";
    int file=open(path,O_WRONLY|O_CREAT|O_APPEND|O_CLOEXEC|O_NOFOLLOW,0600);
    if(file<0)return;
    struct stat info{};
    if(fstat(file,&info)!=0 || info.st_size>262144){
        close(file);
        return;
    }
    char buffer[256];
    std::size_t total=0;
    while(total<4096){
        const auto remaining=std::min<std::size_t>(sizeof buffer,4096-total);
        const ssize_t amount=read(client,buffer,remaining);
        if(amount<=0)break;
        total+=static_cast<std::size_t>(amount);
        for(ssize_t pos=0;pos<amount;){
            ssize_t written=write(file,buffer+pos,static_cast<std::size_t>(amount-pos));
            if(written<=0){close(file);return;}
            pos+=written;
        }
    }
    close(file);
}
#endif
bool clear_error(JNIEnv* env){
    if (!env->ExceptionCheck()) return false;
    env->ExceptionClear();
    return true;
}
std::string read_file(int dir,const char* name,std::size_t limit) {
    int fd=openat(dir,name,O_RDONLY|O_CLOEXEC|O_NOFOLLOW);
    if (fd<0)return {};
    struct stat info{};
    if (fstat(fd,&info)!=0 || info.st_size<0 ||
        static_cast<std::uint64_t>(info.st_size)>limit){close(fd);return {};}
    std::string result;
    result.resize(static_cast<std::size_t>(info.st_size));
    std::size_t offset=0;
    while(offset<result.size()){
        ssize_t n=read(fd,result.data()+offset,result.size()-offset);
        if(n<=0){result.clear();break;}
        offset+=static_cast<std::size_t>(n);
    }
    close(fd);
    return result;
}
bool starts_process(std::string_view process,std::string_view package){
    return !package.empty() && (process==package ||
        (process.size()>package.size() && process.substr(0,package.size())==package &&
         process[package.size()]==':'));
}
bool match_process(std::string_view process,const std::string& known){
    // Known processes are derived from PackageManager; no SDK/model gates.
    std::size_t start=0;
    while(start<known.size()){
        auto end=known.find('\n',start);
        if(end==std::string::npos)end=known.size();
        std::string_view pkg(known.data()+start,end-start);
        if(starts_process(process,pkg))return true;
        start=end+1;
    }
    // Fall back only to known Xiaomi package names. A random process whose
    // name contains "powerkeeper" must not receive an ART hook library.
    if (known.empty())
        return starts_process(process,"com.miui.powerkeeper") ||
               starts_process(process,"com.xiaomi.powerkeeper");
    return false;
}
std::vector<std::string> read_classes(const std::string& report){
    // Read DEX class descriptors from the on-device PowerKeeperProbe report.
    std::vector<std::string> out;
    std::size_t at=0;
    while((at=report.find('L',at))!=std::string::npos){
        auto tail=report.find(';',at);
        if(tail==std::string::npos || tail-at>220){++at;continue;}
        std::string name=report.substr(at+1,tail-at-1);
        std::replace(name.begin(),name.end(),'/','.');
        if(name.ends_with(".GmsObserver") || name.ends_with(".NetdExecutor") ||
           name.ends_with(".GlobalFeatureConfigureHelper")){
            if(std::find(out.begin(),out.end(),name)==out.end())out.push_back(std::move(name));
        }
        at=tail+1;
    }
    return out;
}
bool init_art(JNIEnv* env){
    symbols=std::make_unique<ArtSymbols>();
    if(!symbols->ready()){symbols.reset();msg(ANDROID_LOG_WARN,"No ART symbols; PowerKeeper Hook disabled");return false;}
    // ART callbacks execute under ScopedSuspendAll; prewarm all symbols now.
    symbols->prewarm();
    lsplant::InitInfo cfg{};
    cfg.inline_hooker=[](void* target,void* replacement)->void*{
        dobby_dummy_func_t original=nullptr;
        const auto replace=reinterpret_cast<dobby_dummy_func_t>(replacement);
        return DobbyHook(target,replace,&original)==0?reinterpret_cast<void*>(original):nullptr;
    };
    cfg.inline_unhooker=[](void* target)->bool{return DobbyDestroy(target)==0;};
    cfg.art_symbol_resolver=[](std::string_view n)->void*{return symbols?symbols->exact(n):nullptr;};
    cfg.art_symbol_prefix_resolver=[](std::string_view p)->void*{return symbols?symbols->prefix(p):nullptr;};
    cfg.generated_class_name="FCMU_PK_";
    cfg.generated_field_name="fcmuCallback";
    cfg.generated_method_name="fcmuBridge";
    cfg.generated_source_name="FCMU";
    art_ready=lsplant::Init(env,cfg);
    if(!art_ready){msg(ANDROID_LOG_WARN,"LSPlant unavailable; PowerKeeper Hook disabled");symbols.reset();}
    return art_ready;
}
jobject hook(JNIEnv* env,jclass,jobject target,jobject owner,jobject callback){
    if(!art_ready || !target || !owner || !callback)return nullptr;
    jobject backup=lsplant::Hook(env,target,owner,callback);
    if(backup!=nullptr) (void)lsplant::Deoptimize(env,target);
    return backup;
}
jclass from_loader(JNIEnv* env,jobject loader,const char* name){
    if(!loader)return nullptr;
    jclass cl=env->FindClass("java/lang/ClassLoader");
    jmethodID load=cl?env->GetMethodID(cl,"loadClass","(Ljava/lang/String;)Ljava/lang/Class;"):nullptr;
    if(!load){clear_error(env);return nullptr;}
    jstring key=env->NewStringUTF(name);
    jobject result=env->CallObjectMethod(loader,load,key);
    clear_error(env);
    env->DeleteLocalRef(key);
    env->DeleteLocalRef(cl);
    return static_cast<jclass>(result);
}
bool activate(JNIEnv* env,int trace_fd){
    (void)trace_fd;
#ifdef FCMU_PK_EXPERIMENT_DIAGNOSTICS
    stage_trace(trace_fd,"activate entered");
#endif
    if(dex.empty()){
        msg(ANDROID_LOG_WARN,"Java bridge DEX is empty; skipping ART init");
        return false;
    }
    #ifdef FCMU_PK_EXPERIMENT_DIAGNOSTICS
    stage_trace(trace_fd,"ART init beginning");
    #endif
    if(!init_art(env)){
#ifdef FCMU_PK_EXPERIMENT_DIAGNOSTICS
        stage_trace(trace_fd,"ART init failed");
#endif
        return false;
    }
#ifdef FCMU_PK_EXPERIMENT_DIAGNOSTICS
    stage_trace(trace_fd,"ART init succeeded");
#endif
    msg(ANDROID_LOG_INFO,"ART init succeeded; preparing Java bridge");
    jbyteArray input=env->NewByteArray(static_cast<jsize>(dex.size()));
    if(!input){clear_error(env);msg(ANDROID_LOG_WARN,"Java bridge: failed to allocate DEX input");return false;}
    env->SetByteArrayRegion(input,0,static_cast<jsize>(dex.size()),reinterpret_cast<const jbyte*>(dex.data()));
    jclass buffers=env->FindClass("java/nio/ByteBuffer");
    jmethodID wrap=buffers?env->GetStaticMethodID(buffers,"wrap","([B)Ljava/nio/ByteBuffer;"):nullptr;
    if(!wrap){clear_error(env);msg(ANDROID_LOG_WARN,"Java bridge: ByteBuffer.wrap unavailable");return false;}
    jobject buffer=env->CallStaticObjectMethod(buffers,wrap,input);
    jclass cl=env->FindClass("java/lang/ClassLoader");
    jmethodID system=cl?env->GetStaticMethodID(cl,"getSystemClassLoader","()Ljava/lang/ClassLoader;"):nullptr;
    if(!system){clear_error(env);msg(ANDROID_LOG_WARN,"Java bridge: system ClassLoader unavailable");return false;}
    jobject parent=env->CallStaticObjectMethod(cl,system);
    jclass im=env->FindClass("dalvik/system/InMemoryDexClassLoader");
    jmethodID ctor=im?env->GetMethodID(im,"<init>","(Ljava/nio/ByteBuffer;Ljava/lang/ClassLoader;)V"):nullptr;
    if(!ctor){clear_error(env);msg(ANDROID_LOG_WARN,"Java bridge: InMemoryDexClassLoader unavailable");return false;}
    jobject loader=env->NewObject(im,ctor,buffer,parent);
    if(!loader || clear_error(env)){msg(ANDROID_LOG_WARN,"Java bridge: DEX ClassLoader construction failed");return false;}
    jclass cls=from_loader(env,loader,"io.github.e3n.fcmu.pk.PowerKeeperRuntimeEntry");
    if(!cls){msg(ANDROID_LOG_WARN,"Java bridge: entry class unresolved");return false;}
    JNINativeMethod natives[]={{
        const_cast<char*>("nativeHook"),
        const_cast<char*>("(Ljava/lang/reflect/Method;Ljava/lang/Object;Ljava/lang/reflect/Method;)Ljava/lang/reflect/Method;"),
        reinterpret_cast<void*>(hook)
    }};
    if(env->RegisterNatives(cls,natives,1)!=JNI_OK || clear_error(env)){
        msg(ANDROID_LOG_WARN,"Java bridge: nativeHook registration failed");
        return false;
    }
    jmethodID prepare=env->GetStaticMethodID(cls,"prepare","([Ljava/lang/String;)Z");
    if(!prepare){clear_error(env);msg(ANDROID_LOG_WARN,"Java bridge: prepare method missing");return false;}
    jclass string_class=env->FindClass("java/lang/String");
    jobjectArray classes=env->NewObjectArray(static_cast<jsize>(detected.size()),string_class,nullptr);
    for(std::size_t i=0;i<detected.size();i++){
        jstring value=env->NewStringUTF(detected[i].c_str());
        env->SetObjectArrayElement(classes,static_cast<jsize>(i),value);
        env->DeleteLocalRef(value);
    }
    jboolean success=env->CallStaticBooleanMethod(cls,prepare,classes);
    bool failed=clear_error(env);
#ifdef FCMU_PK_EXPERIMENT_DIAGNOSTICS
    stage_trace(trace_fd,failed?"Java bridge JNI exception":success?"attach hook prepared":"attach hook unavailable");
#endif
    msg(failed || !success ? ANDROID_LOG_WARN : ANDROID_LOG_INFO,
        failed || !success ? "PowerKeeper hook bridge unavailable; FCM core independent"
                            : "PowerKeeper-only attach hook prepared; per-method checks follow app attach");
    return !failed && success;
}
}

class ScopedPowerKeeper final:public zygisk::ModuleBase {
public:
    void onLoad(zygisk::Api* api,JNIEnv* env) override {api_=api;env_=env;}
    void preAppSpecialize(zygisk::AppSpecializeArgs* args) override {
        if(!args || !args->nice_name)return;
        const char* ptr=env_->GetStringUTFChars(args->nice_name,nullptr);
        if(!ptr)return;
        std::string process(ptr);
        env_->ReleaseStringUTFChars(args->nice_name,ptr);
        const bool diagnostic=process.find("powerkeeper")!=std::string::npos;
#ifdef FCMU_PK_EXPERIMENT_DIAGNOSTICS
        if(diagnostic) {
            trace_fd_=api_->connectCompanion();
            stage_trace(trace_fd_,"preAppSpecialize entered");
        }
#endif
        if(diagnostic) msg(ANDROID_LOG_INFO,"Target-like process reached Zygisk preAppSpecialize");
        int dir=api_->getModuleDir();
        if(dir<0){
            if(diagnostic) msg(ANDROID_LOG_WARN,"Target-like process could not obtain module dir");
#ifdef FCMU_PK_EXPERIMENT_DIAGNOSTICS
            stage_trace(trace_fd_,"module_dir unavailable");
            if(trace_fd_>=0){close(trace_fd_);trace_fd_=-1;}
#endif
            api_->setOption(zygisk::Option::DLCLOSE_MODULE_LIBRARY);
            return;
        }
        std::string pk_processes=read_file(dir,"backend/powerkeeper-packages.list",4096);
        chosen_=match_process(process,pk_processes);
        if(chosen_){
            auto contents=read_file(dir,"powerkeeper-runtime.dex",2*1024*1024);
            dex.assign(contents.begin(),contents.end());
            detected=read_classes(read_file(dir,"backend/powerkeeper-capabilities.tsv",65536));
        }
        close(dir);
        if(diagnostic){
            if(!chosen_) msg(ANDROID_LOG_WARN,"PowerKeeper target rejected by package-name contract");
            else if(dex.empty()) msg(ANDROID_LOG_WARN,"PowerKeeper selected but bridge DEX missing");
            else msg(ANDROID_LOG_INFO,"PowerKeeper target chosen with bridge DEX");
#ifdef FCMU_PK_EXPERIMENT_DIAGNOSTICS
            stage_trace(trace_fd_,!chosen_?"process rejected":
                       dex.empty()?"DEX absent":"target selected, DEX loaded");
#endif
        }
        if(!chosen_ || dex.empty()) {
            chosen_=false;
            api_->setOption(zygisk::Option::DLCLOSE_MODULE_LIBRARY);
        }
#ifdef FCMU_PK_EXPERIMENT_DIAGNOSTICS
        // A socket opened in pre-specialize is not guaranteed to survive
        // app UID / SELinux specialization. Flush and close before crossing.
        if(trace_fd_>=0){close(trace_fd_);trace_fd_=-1;}
#endif
    }
    void postAppSpecialize(const zygisk::AppSpecializeArgs*) override {
#ifdef FCMU_PK_EXPERIMENT_DIAGNOSTICS
        // The pre-specialize Companion socket was intentionally closed;
        // establish a fresh companion from this app security context.
        if(chosen_ && api_)trace_fd_=api_->connectCompanion();
        stage_trace(trace_fd_,"postAppSpecialize entered");
#endif
        if(chosen_ && env_){
            msg(ANDROID_LOG_INFO,"PowerKeeper entered Zygisk postAppSpecialize");
            bool active=activate(env_,
#ifdef FCMU_PK_EXPERIMENT_DIAGNOSTICS
                trace_fd_
#else
                -1
#endif
            );
            (void)active;
#ifdef FCMU_PK_EXPERIMENT_DIAGNOSTICS
            stage_trace(trace_fd_,active?"bridge prepared":"bridge failed or not installed");
#endif
        }
#ifdef FCMU_PK_EXPERIMENT_DIAGNOSTICS
        if(trace_fd_>=0){close(trace_fd_);trace_fd_=-1;}
#endif
    }
private:
    zygisk::Api* api_=nullptr;
    JNIEnv* env_=nullptr;
    bool chosen_=false;
#ifdef FCMU_PK_EXPERIMENT_DIAGNOSTICS
    int trace_fd_=-1;
#endif
};
#ifdef FCMU_PK_EXPERIMENT_DIAGNOSTICS
REGISTER_ZYGISK_COMPANION(companion_trace)
#endif
REGISTER_ZYGISK_MODULE(ScopedPowerKeeper)

#ifdef FCMU_ART_ISOLATED_TEST
// Explicit opt-in, isolated app_process-only JNI entry point. This library
// MUST NOT be packaged in the Magisk module or installed as a Zygisk payload.
extern "C" JNIEXPORT jint JNICALL Java_ArtInitSelfTest_runInit(JNIEnv* env, jclass) {
    msg(ANDROID_LOG_INFO, "ART selftest: initializing LSPlant in disposable process");
    return init_art(env) ? 1 : 0;
}

 // The test-only method is available solely in libfcmu_pk_selftest.so.
 // Its target and callback classes live inside the disposable app_process
 // driver, never inside PowerKeeper or system_server.
 extern "C" JNIEXPORT jint JNICALL Java_ArtInitSelfTest_installHook(JNIEnv* env, jclass) {
     if (!art_ready) return 0;
     jclass target=env->FindClass("ArtInitSelfTest$Target");
     jclass hooker=env->FindClass("ArtInitSelfTest$Hooker");
     if (!target || !hooker) {clear_error(env);return 0;}
     jmethodID original=env->GetMethodID(target,"answer","(I)I");
     jmethodID callback=env->GetMethodID(hooker,"callback","([Ljava/lang/Object;)Ljava/lang/Object;");
     jmethodID ctor=env->GetMethodID(hooker,"<init>","()V");
     if (!original || !callback || !ctor) {clear_error(env);return 0;}
     jobject originalMethod=env->ToReflectedMethod(target,original,JNI_FALSE);
     jobject callbackMethod=env->ToReflectedMethod(hooker,callback,JNI_FALSE);
     jobject hookerObject=env->NewObject(hooker,ctor);
     if (!originalMethod || !callbackMethod || !hookerObject || clear_error(env)) return 0;
     jobject backup=lsplant::Hook(env,originalMethod,hookerObject,callbackMethod);
     if (!backup || clear_error(env)) return 0;
     return lsplant::IsHooked(env,originalMethod) ? 1 : 0;
 }

#endif
