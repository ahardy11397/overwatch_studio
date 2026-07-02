#include "FFmpegCaptureSource.h"
#include <d3d11.h>
#include <wrl/client.h>

extern "C" {
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libavutil/imgutils.h>
#include <libswscale/swscale.h>
}

using Microsoft::WRL::ComPtr;

struct FFmpegCaptureSource::FFmpegState {
    AVFormatContext* formatCtx = nullptr;
    AVCodecContext* codecCtx = nullptr;
    AVFrame* frame = nullptr;
    AVFrame* rgbFrame = nullptr;
    SwsContext* swsCtx = nullptr;
    int videoStreamIndex = -1;
    uint64_t frameCounter = 0;
};

FFmpegCaptureSource::FFmpegCaptureSource() noexcept = default;

FFmpegCaptureSource::~FFmpegCaptureSource() {
    close();
}

bool FFmpegCaptureSource::open(const std::string& url, ID3D11Device* device) noexcept {
    close();
    m_url = url;
    m_device = device;
    m_state = new FFmpegState();

    avformat_network_init();

    m_state->formatCtx = avformat_alloc_context();
    if (!m_state->formatCtx) return false;

    AVDictionary* opts = nullptr;
    av_dict_set(&opts, "rtsp_transport", "tcp", 0);
    av_dict_set(&opts, "stimeout", "3000000", 0); // 3s timeout

    if (avformat_open_input(&m_state->formatCtx, url.c_str(), nullptr, &opts) != 0) {
        close();
        return false;
    }

    if (avformat_find_stream_info(m_state->formatCtx, nullptr) < 0) {
        close();
        return false;
    }

    for (unsigned int i = 0; i < m_state->formatCtx->nb_streams; ++i) {
        if (m_state->formatCtx->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_VIDEO) {
            m_state->videoStreamIndex = static_cast<int>(i);
            break;
        }
    }
    if (m_state->videoStreamIndex < 0) {
        close();
        return false;
    }

    AVCodecParameters* codecpar = m_state->formatCtx->streams[m_state->videoStreamIndex]->codecpar;
    const AVCodec* codec = avcodec_find_decoder(codecpar->codec_id);
    if (!codec) { close(); return false; }

    m_state->codecCtx = avcodec_alloc_context3(codec);
    avcodec_parameters_to_context(m_state->codecCtx, codecpar);
    if (avcodec_open2(m_state->codecCtx, codec, nullptr) < 0) { close(); return false; }

    m_width = m_state->codecCtx->width;
    m_height = m_state->codecCtx->height;

    m_state->frame = av_frame_alloc();
    m_state->rgbFrame = av_frame_alloc();
    return true;
}

void FFmpegCaptureSource::close() noexcept {
    stop();
    if (m_state) {
        if (m_state->swsCtx) sws_freeContext(m_state->swsCtx);
        if (m_state->rgbFrame) av_frame_free(&m_state->rgbFrame);
        if (m_state->frame) av_frame_free(&m_state->frame);
        if (m_state->codecCtx) avcodec_free_context(&m_state->codecCtx);
        if (m_state->formatCtx) avformat_close_input(&m_state->formatCtx);
        avformat_network_deinit();
        delete m_state;
        m_state = nullptr;
    }
    if (m_texture) { m_texture->Release(); m_texture = nullptr; }
}

bool FFmpegCaptureSource::start(FrameCallback callback) noexcept {
    if (!m_state || m_running.load()) return false;
    m_callback = std::move(callback);
    m_running.store(true);
    m_thread = std::thread(&FFmpegCaptureSource::captureLoop, this);
    return true;
}

void FFmpegCaptureSource::stop() noexcept {
    m_running.store(false);
    if (m_thread.joinable()) m_thread.join();
}

void FFmpegCaptureSource::captureLoop() noexcept {
    // Create D3D11 staging texture for YUV->RGB conversion output
    D3D11_TEXTURE2D_DESC desc = {};
    desc.Width = static_cast<UINT>(m_width);
    desc.Height = static_cast<UINT>(m_height);
    desc.MipLevels = 1;
    desc.ArraySize = 1;
    desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
    desc.SampleDesc.Count = 1;
    desc.Usage = D3D11_USAGE_DYNAMIC;
    desc.BindFlags = D3D11_BIND_SHADER_RESOURCE;
    desc.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;

    ComPtr<ID3D11Device> device;
    m_device->AddRef();
    device.Attach(m_device);

    ComPtr<ID3D11DeviceContext> ctx;
    device->GetImmediateContext(ctx.GetAddressOf());

    HRESULT hr = device->CreateTexture2D(&desc, nullptr, &m_texture);
    if (FAILED(hr)) { m_running.store(false); return; }

    m_state->swsCtx = sws_getContext(
        m_width, m_height, m_state->codecCtx->pix_fmt,
        m_width, m_height, AV_PIX_FMT_BGRA,
        SWS_BILINEAR, nullptr, nullptr, nullptr
    );
    if (!m_state->swsCtx) { m_running.store(false); return; }

    int rgbBufSize = av_image_alloc(
        m_state->rgbFrame->data, m_state->rgbFrame->linesize,
        m_width, m_height, AV_PIX_FMT_BGRA, 32
    );
    if (rgbBufSize < 0) { m_running.store(false); return; }

    AVPacket* packet = av_packet_alloc();
    if (!packet) { m_running.store(false); return; }

    while (m_running.load()) {
        int ret = av_read_frame(m_state->formatCtx, packet);
        if (ret < 0) {
            // Stream ended or error — wait before retry for live streams
            if (ret == AVERROR_EOF) break;
            std::this_thread::sleep_for(std::chrono::milliseconds(10));
            continue;
        }

        if (packet->stream_index == m_state->videoStreamIndex) {
            avcodec_send_packet(m_state->codecCtx, packet);

            while (avcodec_receive_frame(m_state->codecCtx, m_state->frame) == 0) {
                sws_scale(m_state->swsCtx,
                    m_state->frame->data, m_state->frame->linesize,
                    0, m_height,
                    m_state->rgbFrame->data, m_state->rgbFrame->linesize);

                D3D11_MAPPED_SUBRESOURCE mapped;
                if (SUCCEEDED(ctx->Map(m_texture, 0, D3D11_MAP_WRITE_DISCARD, 0, &mapped))) {
                    uint8_t* src = m_state->rgbFrame->data[0];
                    int srcStride = m_state->rgbFrame->linesize[0];
                    for (int y = 0; y < m_height; ++y) {
                        memcpy(static_cast<uint8_t*>(mapped.pData) + y * mapped.RowPitch,
                               src + y * srcStride, static_cast<size_t>(m_width * 4));
                    }
                    ctx->Unmap(m_texture, 0);
                }

                uint64_t pts = m_state->frameCounter++;
                if (m_callback) m_callback(m_texture, pts);
            }
        }
        av_packet_unref(packet);
    }

    av_freep(&m_state->rgbFrame->data[0]);
    av_packet_free(&packet);
}
