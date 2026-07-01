#include "FFmpegCaptureSource.h"
#include <d3d11.h>

extern "C" {
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libavutil/imgutils.h>
#include <libswscale/swscale.h>
}

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
    av_dict_set(&opts, "stimeout", "5000000", 0); // 5s timeout

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
    if (!codec) {
        close();
        return false;
    }

    m_state->codecCtx = avcodec_alloc_context3(codec);
    if (!m_state->codecCtx) {
        close();
        return false;
    }
    avcodec_parameters_to_context(m_state->codecCtx, codecpar);
    if (avcodec_open2(m_state->codecCtx, codec, nullptr) < 0) {
        close();
        return false;
    }

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
        delete m_state;
        m_state = nullptr;
    }
    if (m_texture) {
        m_texture->Release();
        m_texture = nullptr;
    }
}

bool FFmpegCaptureSource::start(FrameCallback callback) noexcept {
    if (!m_state || m_running.load()) return false;
    m_callback = std::move(callback);
    m_running.store(true);
    m_thread = std::thread(&FFmpegCaptureSource::captureLoop, this, m_device);
    return true;
}

void FFmpegCaptureSource::stop() noexcept {
    m_running.store(false);
    if (m_thread.joinable()) {
        m_thread.join();
    }
}

void FFmpegCaptureSource::captureLoop(ID3D11Device* device) noexcept {
    D3D11_TEXTURE2D_DESC texDesc = {};
    texDesc.Width = static_cast<UINT>(m_width);
    texDesc.Height = static_cast<UINT>(m_height);
    texDesc.MipLevels = 1;
    texDesc.ArraySize = 1;
    texDesc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
    texDesc.SampleDesc.Count = 1;
    texDesc.Usage = D3D11_USAGE_DYNAMIC;
    texDesc.BindFlags = D3D11_BIND_SHADER_RESOURCE;
    texDesc.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;

    HRESULT hr = device->CreateTexture2D(&texDesc, nullptr, &m_texture);
    if (FAILED(hr)) {
        m_running.store(false);
        return;
    }

    ID3D11DeviceContext* ctx = nullptr;
    device->GetImmediateContext(&ctx);

    // ponytail: single-threaded decode loop, threaded decode if perf matters
    m_state->swsCtx = sws_getContext(
        m_width, m_height, m_state->codecCtx->pix_fmt,
        m_width, m_height, AV_PIX_FMT_BGRA,
        SWS_BILINEAR, nullptr, nullptr, nullptr
    );

    int rgbBufSize = av_image_alloc(
        m_state->rgbFrame->data, m_state->rgbFrame->linesize,
        m_width, m_height, AV_PIX_FMT_BGRA, 32);

    AVPacket pkt;
    av_init_packet(&pkt);

    while (m_running.load(std::memory_order_relaxed)) {
        int ret = av_read_frame(m_state->formatCtx, &pkt);
        if (ret < 0) {
            // ponytail: EOF or error, loop restarts for live streams
            if (ret == AVERROR_EOF && m_state->formatCtx->pb &&
                (m_state->formatCtx->iformat->flags & AVFMT_NOFILE) == 0) {
                // ponytail: file source EOF, stop
                break;
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(10));
            av_packet_unref(&pkt);
            continue;
        }

        if (pkt.stream_index == m_state->videoStreamIndex) {
            avcodec_send_packet(m_state->codecCtx, &pkt);

            while (avcodec_receive_frame(m_state->codecCtx, m_state->frame) == 0) {
                sws_scale(m_state->swsCtx,
                    m_state->frame->data, m_state->frame->linesize,
                    0, m_height,
                    m_state->rgbFrame->data, m_state->rgbFrame->linesize);

                D3D11_MAPPED_SUBRESOURCE mapped;
                if (SUCCEEDED(ctx->Map(m_texture, 0, D3D11_MAP_WRITE_DISCARD, 0, &mapped))) {
                    const uint8_t* src = m_state->rgbFrame->data[0];
                    uint8_t* dst = static_cast<uint8_t*>(mapped.pData);
                    for (int y = 0; y < m_height; ++y) {
                        memcpy(dst + y * mapped.RowPitch,
                               src + y * m_state->rgbFrame->linesize[0],
                               static_cast<size_t>(m_width) * 4);
                    }
                    ctx->Unmap(m_texture, 0);
                }

                uint64_t pts = m_state->frameCounter++;
                if (m_callback) {
                    m_callback(m_texture, pts);
                }
            }
        }
        av_packet_unref(&pkt);
    }

    if (ctx) ctx->Release();
    av_freep(&m_state->rgbFrame->data[0]);
    av_packet_unref(&pkt);
    m_running.store(false);
}