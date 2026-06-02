#pragma once
#include <fstream>
#include <vector>
#include <string>
#include <algorithm>
#include <cstdint>

class WavFileWriter {
public:
    WavFileWriter() = default;
    ~WavFileWriter() { close(); }

    bool open(const std::string& filePath, uint32_t sampleRate) {
        m_file.open(filePath, std::ios::binary);
        if (!m_file.is_open()) return false;
        m_sampleRate = sampleRate;
        m_totalDataBytes = 0;

        std::vector<char> placeholder(44, 0);
        m_file.write(placeholder.data(), placeholder.size());
        return true;
    }

    void writeSamples(const float* floatSamples, size_t count) {
        if (!m_file.is_open()) return;

        std::vector<uint8_t> bytes;
        bytes.reserve(count * 3);

        for (size_t i = 0; i < count; ++i) {
            float clamped = std::max(-1.0f, std::min(1.0f, floatSamples[i]));
            int32_t val = static_cast<int32_t>(clamped * 8388607.0f);
            bytes.push_back(static_cast<uint8_t>(val & 0xFF));
            bytes.push_back(static_cast<uint8_t>((val >> 8) & 0xFF));
            bytes.push_back(static_cast<uint8_t>((val >> 16) & 0xFF));
        }

        m_file.write(reinterpret_cast<const char*>(bytes.data()), bytes.size());
        m_totalDataBytes += bytes.size();
    }

    void close() {
        if (!m_file.is_open()) return;

        m_file.seekp(0);
        uint32_t fileSizeMinus8 = 36 + m_totalDataBytes;
        uint32_t subChunk1Size = 16;
        uint16_t audioFormat = 1;
        uint16_t numChannels = 1;
        uint16_t bitsPerSample = 24;
        uint16_t blockAlign = 3;
        uint32_t byteRate = m_sampleRate * blockAlign;

        m_file.write("RIFF", 4);
        m_file.write(reinterpret_cast<const char*>(&fileSizeMinus8), 4);
        m_file.write("WAVEfmt ", 8);
        m_file.write(reinterpret_cast<const char*>(&subChunk1Size), 4);
        m_file.write(reinterpret_cast<const char*>(&audioFormat), 2);
        m_file.write(reinterpret_cast<const char*>(&numChannels), 2);
        m_file.write(reinterpret_cast<const char*>(&m_sampleRate), 4);
        m_file.write(reinterpret_cast<const char*>(&byteRate), 4);
        m_file.write(reinterpret_cast<const char*>(&blockAlign), 2);
        m_file.write(reinterpret_cast<const char*>(&bitsPerSample), 2);
        m_file.write("data", 4);
        m_file.write(reinterpret_cast<const char*>(&m_totalDataBytes), 4);

        m_file.close();
    }

private:
    std::ofstream m_file;
    uint32_t m_sampleRate = 48000;
    uint32_t m_totalDataBytes = 0;
};
