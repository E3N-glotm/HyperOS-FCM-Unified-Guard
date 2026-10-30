#!/usr/bin/env python3
"""Backport the ART initialization ordering from LSPlant's 2026-10-05 fix.

Target: b2f9279014091c83faac094c5fc7c5498261ace8 (pre std-module
toolchain switch). Fail closed if upstream text diverges. This is NOT a
claim of actual on-device ART hook safety; device crash/delivery tests remain
required.
"""

from pathlib import Path
import argparse

BASE = Path(__file__).resolve().parent / "third_party/lsplant/lsplant/src/main/jni"


def replace_once(text: str, before: str, after: str, source: str) -> str:
    if text.count(before) != 1:
        raise RuntimeError(f"unsafe LSPlant patch: {source} expected one anchor, found {text.count(before)}")
    return text.replace(before, after, 1)


def patch_file(path: str, callback):
    file = BASE / path
    old = file.read_text(encoding="utf-8")
    new = callback(old)
    if new == old:
        raise RuntimeError(f"no change to {path}")
    file.write_text(new, encoding="utf-8")


def art_method(src):
    # JNI preparation must not call an inline hooker, even on Android M.
    src = replace_once(src,
        """            } else if (!handler(GetQuickFrameInfo_)) [[unlikely]] {
                LOGW("Failed to hook GetQuickFrameInfo, hooking proxy method may crash");
            }
""",
        """            }
""", "art_method JNI phase")
    # Replace the entire 'else if' branch including its close brace.
    anchor = """    static size_t GetEntryPointOffset() { return entry_point_offset; }"""
    inject = """    // Hook-only phase, after the ART GC guard and thread suspension.
    static void InitHooks(const HookHandler &handler) {
        if (GetAndroidApiLevel() == kSdkMarshmallow && abstract_method_ &&
            abstract_method_->IsAbstract() && !handler(GetQuickFrameInfo_)) {
            LOGW("GetQuickFrameInfo Hook not available; proxy Hook may be unsupported");
        }
    }

"""
    return replace_once(src, anchor, inject+anchor, "art_method post-init")


def class_linker(src):
    begin = """    static bool Init(JNIEnv *env, const HookHandler &handler) {
        int sdk_int = GetAndroidApiLevel();

        if (sdk_int >= kSdkNougat"""
    replacement = """    static bool Init(JNIEnv *env, const HookHandler &handler) {
        // Symbol/JNI preparation only. No ART inline hooks before suspend.
        if (!handler(SetEntryPointsToInterpreter_)) {
            if (handler(GetOptimizedCodeFor_, GetOptimizedCodeForL_, true)) {
                auto obj = JNI_FindClass(env, "java/lang/Object");
                if (!obj) return false;
                auto method = JNI_GetMethodID(env, obj, "equals", "(Ljava/lang/Object;)Z");
                if (!method) return false;
                auto dummy = ArtMethod::FromReflectedMethod(
                    env, JNI_ToReflectedMethod(env, obj, method, false).get())->Clone();
                JavaDebuggableGuard guard;
                dummy->SetNonNative();
                art_quick_to_interpreter_bridge_ = GetOptimizedCodeFor(dummy.get());
            } else if (!handler(art_quick_to_interpreter_bridge_)) {
                return false;
            }
        }
        return true;
    }

    // No JNI is allowed in this region. Must be called under suspension.
    static bool InitHooks(const HookHandler &handler) {
        int sdk_int = GetAndroidApiLevel();

        if (sdk_int >= kSdkNougat"""
    src = replace_once(src,begin,replacement,"class_linker prepare/hook split")
    # Delete original JNI fallback that follows the ART hook installation.
    old = """        if (!handler(SetEntryPointsToInterpreter_)) [[likely]] {
            if (handler(GetOptimizedCodeFor_, GetOptimizedCodeForL_, true)) [[likely]] {
                auto obj = JNI_FindClass(env, "java/lang/Object");
                if (!obj) {
                    return false;
                }
                auto method = JNI_GetMethodID(env, obj, "equals", "(Ljava/lang/Object;)Z");
                if (!method) {
                    return false;
                }
                auto dummy = ArtMethod::FromReflectedMethod(
                        env, JNI_ToReflectedMethod(env, obj, method, false).get())->Clone();
                JavaDebuggableGuard guard;
                // just in case
                dummy->SetNonNative();
                art_quick_to_interpreter_bridge_ = GetOptimizedCodeFor(dummy.get());
            } else if (!handler(art_quick_to_interpreter_bridge_)) [[unlikely]] {
                return false;
            }
            LOGD("art_quick_to_interpreter_bridge = %p", &art_quick_to_interpreter_bridge_);
        }
"""
    return replace_once(src,old,"", "class_linker remove hook-phase JNI")



def hook_helper(src):
    # A thread that reaches a partially published ART callback waits for Init
    # to finish. Reentry by the initializing thread remains permitted.
    src = replace_once(src, "#include <array>\n",
        "#include <array>\n#include <atomic>\n#include <thread>\n#include <utility>\n",
        "hook_helper includes")
    src = replace_once(src, "struct HookHandler {\n",
        """struct HookHandler {
private:
    inline static std::atomic<std::thread::id> initializing_{};
    static_assert(std::atomic<std::thread::id>::is_always_lock_free);
public:
    class InitScope {
    public:
        InitScope() { initializing_.store(std::this_thread::get_id(), std::memory_order_relaxed); }
        InitScope(const InitScope&) = delete;
        InitScope& operator=(const InitScope&) = delete;
        ~InitScope() {
            initializing_.store(std::thread::id{}, std::memory_order_release);
            initializing_.notify_all();
        }
    };
    static void WaitForInitialization() {
        auto owner=initializing_.load(std::memory_order_acquire);
        if (owner==std::thread::id{} || owner==std::this_thread::get_id()) return;
        do {
            initializing_.wait(owner,std::memory_order_acquire);
            owner=initializing_.load(std::memory_order_acquire);
        } while(owner!=std::thread::id{} && owner!=std::this_thread::get_id());
    }
""", "hook_helper InitScope")
    point = "template <typename F>\nconcept Backup"
    adapter = """// Strongly typed callback trampoline; no JNI, mutex or dynamic allocations.
template <auto Function> struct WaitedCallback;
template <typename R, typename... Args, R(*Function)(Args...)>
struct WaitedCallback<Function> {
    static R invoke(Args... args) {
        HookHandler::WaitForInitialization();
        return Function(std::forward<Args>(args)...);
    }
};

"""
    src = replace_once(src,point,adapter+point,"hook_helper typed callback")
    pattern = """                return HookerType {
                    static_cast<decltype(HookerType::replace_)>(
                        &F::template operator()<HookerType::operator()>)
                };"""
    replacement = """                constexpr auto callback = static_cast<decltype(HookerType::replace_)>(
                        &F::template operator()<HookerType::operator()>);
                return HookerType { &WaitedCallback<callback>::invoke };"""
    if src.count(pattern)!=2:
        raise RuntimeError(f"hook_helper expected both pointer branches, got {src.count(pattern)}")
    src = src.replace(pattern,replacement)
    return src


def no_jni_while_suspended(src, filename):
    before = "static bool Init(JNIEnv *env, const HookHandler &handler) {"
    after = "static bool Init(bool java_debuggable, const HookHandler &handler) {"
    src = replace_once(src,before,after,filename+" signature")
    return replace_once(src,"IsJavaDebuggable(env)","java_debuggable",filename+" JNI call")


def core(src):
    begin=src.index("bool InitNative(JNIEnv *env, const HookHandler &handler) {")
    end=src.index("\nstd::tuple<jclass",begin)
    previous=src[begin:end]
    # These must be completely resolved before blocking ART threads.
    new="""bool InitNative(JNIEnv *env, const HookHandler &handler) {
    if (!ArtMethod::Init(env, handler)) return false;
    UpdateTrampoline(ArtMethod::GetEntryPointOffset());
    if (!Thread::Init(handler)) return false;
    if (!Runtime::Init(handler)) return false;
    if (!ClassLinker::Init(env, handler)) return false;
    if (!ScopedSuspendAll::Init(handler)) return false;
    if (!ScopedGCCriticalSection::Init(handler)) return false;
    if (!DexFile::Init(env, handler)) return false;

    // JNI must finish while threads are running and before taking ART locks.
    const bool java_debuggable = IsJavaDebuggable(env);
    ScopedGCCriticalSection gc(Thread::Current(), art::gc::kGcCauseDebugger,
                              art::gc::kCollectorTypeDebugger);
    ScopedSuspendAll suspended("FCMU LSPlant Init", false);
    // Do not call JNI between these guards and their destructors.
    // Publish callback barrier only during ART internal hook installation.
    HookHandler::InitScope init_scope;
    ArtMethod::InitHooks(handler);
    if (!Class::Init(handler)) return false;
    if (!ClassLinker::InitHooks(handler)) return false;
    if (!JitCodeCache::Init(handler)) return false;
    if (!Jit::Init(handler)) return false;
    if (!Instrumentation::Init(java_debuggable, handler)) return false;
    if (!JniIdManager::Init(java_debuggable, handler)) return false;
    if (java_debuggable) {
        Runtime::Current()->SetJavaDebuggable(Runtime::RuntimeDebugState::kNonJavaDebuggable);
    }
    return true;
}
"""
    assert "ScopedSuspendAll" in previous and "IsJavaDebuggable(env)" in previous
    return src[:begin]+new+src[end:]


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--verify", action="store_true")
    args=parser.parse_args()
    rules = {
      "art/runtime/art_method.cxx":art_method,
      "art/runtime/class_linker.cxx":class_linker,
      "art/runtime/instrumentation.cxx":lambda s:no_jni_while_suspended(s,"instrumentation"),
      "art/runtime/jni/jni_id_manager.cxx":lambda s:no_jni_while_suspended(s,"jni_id_manager"),
      "lsplant.cc":core,
      "include/utils/hook_helper.hpp":hook_helper,
    }
    if args.verify:
        data={p:(BASE/p).read_text(encoding="utf8") for p in rules}
        assert "ScopedSuspendAll suspended" in data["lsplant.cc"]
        assert "ScopedGCCriticalSection gc" in data["lsplant.cc"]
        hooked=data["lsplant.cc"].split("ScopedSuspendAll suspended",1)[1].split("\nstd::tuple<jclass",1)[0]
        assert "JNI_" not in hooked and "IsJavaDebuggable(env)" not in hooked
        assert "InitHooks(handler)" in hooked
        assert "HookHandler::InitScope init_scope" in hooked
        helper=data["include/utils/hook_helper.hpp"]
        assert "WaitedCallback<callback>::invoke" in helper
        assert "WaitForInitialization()" in helper
        assert "JNI_FindClass" not in data["art/runtime/class_linker.cxx"].split("static bool InitHooks",1)[1]
        print("LSPLANT_INIT_ORDER_STATIC_VERIFICATION_PASS")
        return
    for path,callback in rules.items():patch_file(path,callback)
    main_verify = [str(BASE/p) for p in rules]
    print("LSPLANT_INIT_ORDER_PATCH_APPLIED " + " ".join(main_verify))
    # Execute the same invariants immediately, before any compilation.
    data=(BASE/"lsplant.cc").read_text()
    assert "ScopedSuspendAll suspended" in data


if __name__=="__main__":
    main()
