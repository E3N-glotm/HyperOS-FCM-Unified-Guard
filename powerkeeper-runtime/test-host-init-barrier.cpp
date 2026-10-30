// Host-only synchronization regression, not a device ART test.
// Exercises the exact typed callback trampoline used in the LSPlant backport.
#include "utils/hook_helper.hpp"
#include <atomic>
#include <cassert>
#include <chrono>
#include <thread>

static int original(int x) { return x + 1; }

int main() {
    std::atomic<bool> waiting{false};
    std::atomic<bool> finished{false};
    std::atomic<int> result{0};
    std::thread worker;
    {
        lsplant::HookHandler::InitScope initialization;
        // Same-thread reentry cannot deadlock.
        assert(lsplant::WaitedCallback<&original>::invoke(1) == 2);
        worker = std::thread([&] {
            waiting.store(true, std::memory_order_release);
            result.store(lsplant::WaitedCallback<&original>::invoke(41),
                         std::memory_order_relaxed);
            finished.store(true, std::memory_order_release);
        });
        while (!waiting.load(std::memory_order_acquire)) std::this_thread::yield();
        std::this_thread::sleep_for(std::chrono::milliseconds(40));
        assert(!finished.load(std::memory_order_acquire));
    }
    worker.join();
    assert(finished.load() && result.load() == 42);
    // A second scope simulates an initialization failure/unwind path.
    try {
        lsplant::HookHandler::InitScope initialization;
        throw 1;
    } catch (...) {}
    assert(lsplant::WaitedCallback<&original>::invoke(7) == 8);
    return 0;
}
