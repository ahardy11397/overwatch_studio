#pragma once

#include <string>
#include <atomic>
#include <thread>
#include <functional>
#include <cstdint>

struct ID3D11Texture2D;
struct ID3D11Device;

class FFmpegCaptureSource {
public:
    using FrameCallback = std::function<void(ID3D11Texture2D* texture, uint64_t pts)>;

    FFmpegCaptureSource() noexcept;
    ~FFmpegCaptureSource();

    FFmpegCaptureSource(const FFmpegCaptureSource&) = delete;
    FFmpegCaptureSource& operator=(const FFmpegCaptureSource&) = delete;

    bool open(const std::string& url, ID3D11Device* device) noexcept;
    void close() noexcept;
    bool start(FrameCallback callback) noexcept;
    void stop() noexcept;

    bool isRunning() const noexcept { return m_running.load(std::memory_order_relaxed); }
    int getWidth() const noexcept { return m_width; }
    int getHeight() const noexcept { return m_height; }

private:
    void captureLoop(ID3D11Device* device) noexcept;

    std::string m_url;
    ID3D11Device* m_device = nullptr;
    ID3D11Texture2D* m_texture = nullptr;
    int m_width = 0;
    int m_height = 0;

    std::atomic<bool> m_running{false};
    std::thread m_thread;
    FrameCallback m_callback;

    struct FFmpegState;
    FFmpegState* m_state = nullptr;
};