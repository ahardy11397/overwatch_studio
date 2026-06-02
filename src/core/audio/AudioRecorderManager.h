#pragma once
#include "WavFileWriter.h"
#include "../control/SPSCQueue.h"
#include <thread>
#include <atomic>
#include <vector>
#include <array>
#include <memory>
#include <filesystem>

struct AudioRecordBlock {
    static constexpr size_t BlockSize = 256;
    std::array<float, BlockSize> samples;
    size_t count = 0;
};

class AudioRecorderManager {
public:
    AudioRecorderManager() : m_active(false) {}
    ~AudioRecorderManager() { stopSession(); }

    void initialize(size_t channelCount, const std::string& sessionName) {
        m_channelCount = channelCount;
        m_sessionName = sessionName;
        
        m_queues.clear();
        for (size_t i = 0; i < m_channelCount; ++i) {
            m_queues.push_back(std::make_unique<SPSCQueue<AudioRecordBlock>>(2048));
        }
    }

    void startSession(uint32_t sampleRate) {
        if (m_active.load()) return;
        m_sampleRate = sampleRate;
        m_active.store(true);

        std::filesystem::create_directories(m_sessionName);

        m_writerThread = std::thread([this]() {
            std::vector<std::unique_ptr<WavFileWriter>> writers;
            for (size_t i = 0; i < m_channelCount; ++i) {
                auto writer = std::make_unique<WavFileWriter>();
                std::string path = m_sessionName + "/track_" + std::to_string(i + 1) + ".wav";
                writer->open(path, m_sampleRate);
                writers.push_back(std::move(writer));
            }

            while (m_active.load()) {
                bool processedAny = false;
                for (size_t i = 0; i < m_channelCount; ++i) {
                    if (auto blockOpt = m_queues[i]->pop()) {
                        writers[i]->writeSamples(blockOpt->samples.data(), blockOpt->count);
                        processedAny = true;
                      }
                }
                if (!processedAny) {
                    std::this_thread::sleep_for(std::chrono::milliseconds(2));
                }
            }

            // Drain remaining queues
            for (size_t i = 0; i < m_channelCount; ++i) {
                while (auto blockOpt = m_queues[i]->pop()) {
                    writers[i]->writeSamples(blockOpt->samples.data(), blockOpt->count);
                }
                writers[i]->close();
            }
        });
    }

    void stopSession() {
        if (!m_active.load()) return;
        m_active.store(false);
        if (m_writerThread.joinable()) {
            m_writerThread.join();
        }
    }

    bool pushBlock(size_t channelIdx, const AudioRecordBlock& block) noexcept {
        if (!m_active.load() || channelIdx >= m_queues.size()) return false;
        return m_queues[channelIdx]->push(block);
    }

private:
    size_t m_channelCount = 0;
    uint32_t m_sampleRate = 48000;
    std::string m_sessionName;
    std::atomic<bool> m_active;
    std::thread m_writerThread;
    std::vector<std::unique_ptr<SPSCQueue<AudioRecordBlock>>> m_queues;
};
