#include "ArtSymbols.hpp"
#include <zygisk.hpp>
#include <lsplant.hpp>
#include <dobby.h>
#include <android/log.h>
#include <fcntl.h>
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
bool activate(JNIEnv* env){
    if(dex.empty() || !init_art(env))return false;
    jbyteArray input=env->NewByteArray(static_cast<jsize>(dex.size()));
    if(!input){clear_error(env);return false;}
    env->SetByteArrayRegion(input,0,static_cast<jsize>(dex.size()),reinterpret_cast<const jbyte*>(dex.data()));
    jclass buffers=env->FindClass("java/nio/ByteBuffer");
    jmethodID wrap=buffers?env->GetStaticMethodID(buffers,"wrap","([B)Ljava/nio/ByteBuffer;"):nullptr;
    if(!wrap){clear_error(env);return false;}
    jobject buffer=env->CallStaticObjectMethod(buffers,wrap,input);
    jclass cl=env->FindClass("java/lang/ClassLoader");
    jmethodID system=cl?env->GetStaticMethodID(cl,"getSystemClassLoader","()Ljava/lang/ClassLoader;"):nullptr;
    if(!system){clear_error(env);return false;}
    jobject parent=env->CallStaticObjectMethod(cl,system);
    jclass im=env->FindClass("dalvik/system/InMemoryDexClassLoader");
    jmethodID ctor=im?env->GetMethodID(im,"<init>","(Ljava/nio/ByteBuffer;Ljava/lang/ClassLoader;)V"):nullptr;
    if(!ctor){clear_error(env);return false;}
    jobject loader=env->NewObject(im,ctor,buffer,parent);
    if(!loader || clear_error(env))return false;
    jclass cls=from_loader(env,loader,"io.github.e3n.fcmu.pk.PowerKeeperRuntimeEntry");
    if(!cls)return false;
    JNINativeMethod natives[]={{
        const_cast<char*>("nativeHook"),
        const_cast<char*>("(Ljava/lang/reflect/Method;Ljava/lang/Object;Ljava/lang/reflect/Method;)Ljava/lang/reflect/Method;"),
        reinterpret_cast<void*>(hook)
    }};
    if(env->RegisterNatives(cls,natives,1)!=JNI_OK || clear_error(env))return false;
    jmethodID prepare=env->GetStaticMethodID(cls,"prepare","([Ljava/lang/String;)Z");
    if(!prepare){clear_error(env);return false;}
    jclass string_class=env->FindClass("java/lang/String");
    jobjectArray classes=env->NewObjectArray(static_cast<jsize>(detected.size()),string_class,nullptr);
    for(std::size_t i=0;i<detected.size();i++){
        jstring value=env->NewStringUTF(detected[i].c_str());
        env->SetObjectArrayElement(classes,static_cast<jsize>(i),value);
        env->DeleteLocalRef(value);
    }
    jboolean success=env->CallStaticBooleanMethod(cls,prepare,classes);
    bool failed=clear_error(env);
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
        int dir=api_->getModuleDir();
        if(dir<0){api_->setOption(zygisk::Option::DLCLOSE_MODULE_LIBRARY);return;}
        std::string pk_processes=read_file(dir,"backend/powerkeeper-packages.list",4096);
        chosen_=match_process(process,pk_processes);
        if(chosen_){
            auto contents=read_file(dir,"powerkeeper-runtime.dex",2*1024*1024);
            dex.assign(contents.begin(),contents.end());
            detected=read_classes(read_file(dir,"backend/powerkeeper-capabilities.tsv",65536));
        }
        close(dir);
        if(!chosen_ || dex.empty()) {
            chosen_=false;
            api_->setOption(zygisk::Option::DLCLOSE_MODULE_LIBRARY);
        }
    }
    void postAppSpecialize(const zygisk::AppSpecializeArgs*) override {
        if(chosen_ && env_){(void)activate(env_);}
    }
private:
    zygisk::Api* api_=nullptr;
    JNIEnv* env_=nullptr;
    bool chosen_=false;
};
REGISTER_ZYGISK_MODULE(ScopedPowerKeeper)
