#pragma once

#include <string_view>
#include <thread>
#include <fstream>
#include <iostream>
#include <atomic>
#include <chrono>
#include <algorithm>
#include <vector>
#include <mutex>

struct LogMessage {
    char text[256];
};

/**
 * @class RealtimeLogger
 * @brief Zero-allocation asynchronous logging ring buffer designed for real-time threads.
 */
class RealtimeLogger {
public:
    static RealtimeLogger& getInstance() {
        static RealtimeLogger instance;
        return instance;
    }

    /**
     * @brief Pushes a message into the queue. Safe to call inside real-time callbacks.
     */
    void log(std::string_view message) noexcept {
        LogMessage msg{};
        size_t len = std::min(message.length(), sizeof(msg.text) - 1);
        std::copy_n(message.data(), len, msg.text);
        msg.text[len] = '\0';

        std::lock_guard<std::mutex> lock(queueMutex);
        if (queue.size() < 1024) {
            queue.push_back(msg);
        }
    }

    /**
     * @brief Launches the background flushing thread writing logs asynchronously to a file.
     */
    void start(const std::string& filepath) {
        if (running.exchange(true)) return;
        logThread = std::jthread([this, filepath](std::stop_token stopToken) {
            std::ofstream file(filepath, std::ios::app);
            std::vector<LogMessage> localQueue;
            localQueue.reserve(1024);
            
            while (!stopToken.stop_requested()) {
                // Safely copy logs under lock to preserve pre-allocated queue capacity
                {
                    std::lock_guard<std::mutex> lock(queueMutex);
                    if (!queue.empty()) {
                        localQueue.assign(queue.begin(), queue.end());
                        queue.clear();
                    }
                }

                // Process local logs outside the lock to avoid blocking real-time writers
                for (const auto& msg : localQueue) {
                    if (file.is_open()) {
                        file << msg.text << std::endl;
                    }
                    std::cout << "[REALTIME LOG] " << msg.text << std::endl;
                }
                localQueue.clear();

                std::this_thread::sleep_for(std::chrono::milliseconds(50));
            }
            // Flush remaining logs on termination
            {
                std::lock_guard<std::mutex> lock(queueMutex);
                localQueue.assign(queue.begin(), queue.end());
                queue.clear();
            }
            for (const auto& msg : localQueue) {
                if (file.is_open()) {
                    file << msg.text << std::endl;
                }
            }
        });
    }

    void stop() {
        if (!running.exchange(false)) return;
        logThread.request_stop();
        if (logThread.joinable()) {
            logThread.join();
        }
    }

    ~RealtimeLogger() {
        stop();
    }

private:
    RealtimeLogger() : running(false) {
        queue.reserve(1024);
    }

    std::vector<LogMessage> queue;
    std::mutex queueMutex;
    std::jthread logThread;
    std::atomic<bool> running;
};

