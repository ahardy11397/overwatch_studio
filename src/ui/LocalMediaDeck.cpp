#include "LocalMediaDeck.h"
#include <QTimer>
#include <QPainter>
#include <QPainterPath>
#include <QColor>
#include <QPen>
#include <QFont>
#include <cmath>
#include <algorithm>
#include <filesystem>
#include <fstream>

extern "C" {
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/avutil.h>
#include <libavutil/channel_layout.h>
#include <libavutil/opt.h>
#include <libswresample/swresample.h>
}

LocalMediaDeck::LocalMediaDeck(QObject* parent) : QObject(parent) {
    m_tickTimer = new QTimer(this);
    connect(m_tickTimer, &QTimer::timeout, this, &LocalMediaDeck::updateTimerTick);
    m_tickTimer->start(1000);
}

LocalMediaDeck::~LocalMediaDeck() {
    m_tickTimer->stop();
    clearDecoded();
}

void LocalMediaDeck::setPlaying(bool play) {
    if (m_playing.load() != play) {
        m_playing.store(play);
        emit playingChanged();
        emit playbackProgressChanged();
    }
}

void LocalMediaDeck::setPosition(int pos) {
    int dur = m_duration.load();
    int clamped = std::max(0, std::min(pos, dur));
    if (m_position.load() != clamped) {
        m_position.store(clamped);
        // Seek in decoded audio
        std::lock_guard lock(m_decodeMutex);
        if (m_sampleRate > 0 && !m_decodedAudio.empty()) {
            m_readCursor = static_cast<size_t>(clamped) * static_cast<size_t>(m_sampleRate) * static_cast<size_t>(m_numChannels);
            if (m_readCursor >= m_decodedAudio.size()) m_readCursor = 0;
        }
        emit positionChanged();
        emit playbackProgressChanged();
    }
}

QString LocalMediaDeck::filePath() const {
    std::lock_guard<std::mutex> lock(m_fileMutex);
    return m_filePath;
}

void LocalMediaDeck::setFilePath(const QString& path) {
    std::lock_guard<std::mutex> lock(m_fileMutex);
    if (m_filePath != path) {
        m_filePath = path;
        emit filePathChanged();
    }
}

void LocalMediaDeck::setVolume(double vol) {
    double clamped = std::max(0.0, std::min(vol, 1.0));
    if (m_volume.load() != clamped) {
        m_volume.store(clamped);
        emit volumeChanged();
    }
}

void LocalMediaDeck::setLoop(bool lp) {
    if (m_loop.load() != lp) {
        m_loop.store(lp);
        emit loopChanged();
    }
}

double LocalMediaDeck::playbackProgress() const {
    int dur = m_duration.load();
    if (dur <= 0) return 0.0;
    return static_cast<double>(m_position.load()) / dur;
}

void LocalMediaDeck::play() {
    setPlaying(true);
}

void LocalMediaDeck::pause() {
    setPlaying(false);
}

void LocalMediaDeck::stop() {
    setPlaying(false);
    setPosition(0);
}

void LocalMediaDeck::clearDecoded() {
    std::lock_guard lock(m_decodeMutex);
    std::vector<float>().swap(m_decodedAudio);
    m_readCursor = 0;
    m_sampleRate = 48000;
    m_numChannels = 2;
}

bool LocalMediaDeck::decodeFile(const QString& path) {
    clearDecoded();
    std::string pathStr = path.toStdString();

    if (!std::filesystem::exists(pathStr)) return false;

    avformat_network_init();

    AVFormatContext* fmtCtx = avformat_alloc_context();
    if (!fmtCtx) return false;

    if (avformat_open_input(&fmtCtx, pathStr.c_str(), nullptr, nullptr) != 0) {
        avformat_free_context(fmtCtx);
        return false;
    }

    if (avformat_find_stream_info(fmtCtx, nullptr) < 0) {
        avformat_close_input(&fmtCtx);
        return false;
    }

    // Find audio stream
    int audioStreamIdx = -1;
    for (unsigned int i = 0; i < fmtCtx->nb_streams; ++i) {
        if (fmtCtx->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_AUDIO) {
            audioStreamIdx = static_cast<int>(i);
            break;
        }
    }
    if (audioStreamIdx < 0) {
        avformat_close_input(&fmtCtx);
        return false;
    }

    AVCodecParameters* codecpar = fmtCtx->streams[audioStreamIdx]->codecpar;
    const AVCodec* codec = avcodec_find_decoder(codecpar->codec_id);
    if (!codec) { avformat_close_input(&fmtCtx); return false; }

    AVCodecContext* codecCtx = avcodec_alloc_context3(codec);
    avcodec_parameters_to_context(codecCtx, codecpar);
    if (avcodec_open2(codecCtx, codec, nullptr) < 0) {
        avcodec_free_context(&codecCtx);
        avformat_close_input(&fmtCtx);
        return false;
    }

    // Setup resampler to 48kHz stereo float
    SwrContext* swr = swr_alloc();
    if (!swr) { avcodec_free_context(&codecCtx); avformat_close_input(&fmtCtx); return false; }

    AVChannelLayout outLayout = AV_CHANNEL_LAYOUT_STEREO;
    AVChannelLayout* inLayout = &codecCtx->ch_layout;
    if (inLayout->nb_channels == 0) {
        static const AVChannelLayout stereo = AV_CHANNEL_LAYOUT_STEREO;
        inLayout = const_cast<AVChannelLayout*>(&stereo);
    }

    av_opt_set_chlayout(swr, "in_chlayout", inLayout, 0);
    av_opt_set_chlayout(swr, "out_chlayout", &outLayout, 0);
    av_opt_set_sample_fmt(swr, "in_sample_fmt", codecCtx->sample_fmt, 0);
    av_opt_set_sample_fmt(swr, "out_sample_fmt", AV_SAMPLE_FMT_FLT, 0);
    av_opt_set_int(swr, "in_sample_rate", codecCtx->sample_rate, 0);
    av_opt_set_int(swr, "out_sample_rate", 48000, 0);

    if (swr_init(swr) < 0) {
        swr_free(&swr);
        avcodec_free_context(&codecCtx);
        avformat_close_input(&fmtCtx);
        return false;
    }
    if (!swr || swr_init(swr) < 0) {
        if (swr) swr_free(&swr);
        avcodec_free_context(&codecCtx);
        avformat_close_input(&fmtCtx);
        return false;
    }

    // Duration from stream info
    int64_t streamDuration = fmtCtx->duration;
    if (streamDuration <= 0 && fmtCtx->streams[audioStreamIdx]->duration > 0) {
        streamDuration = fmtCtx->streams[audioStreamIdx]->duration *
            av_q2d(fmtCtx->streams[audioStreamIdx]->time_base) * AV_TIME_BASE;
    }
    int durationSec = streamDuration > 0
        ? static_cast<int>(streamDuration / AV_TIME_BASE)
        : 0;

    // Decode all audio frames
    AVPacket* packet = av_packet_alloc();
    AVFrame* frame = av_frame_alloc();
    std::vector<float> allAudio;
    const size_t channelSize = 256; // initial guess per channel

    while (av_read_frame(fmtCtx, packet) >= 0) {
        if (packet->stream_index == audioStreamIdx) {
            avcodec_send_packet(codecCtx, packet);
            while (avcodec_receive_frame(codecCtx, frame) == 0) {
                // Resample to stereo float at 48kHz
                uint8_t* output[2] = {nullptr, nullptr};
                int outSamples = swr_get_out_samples(swr, frame->nb_samples);
                if (av_samples_alloc(output, nullptr, 2, outSamples,
                    AV_SAMPLE_FMT_FLT, 0) < 0) continue;

                int converted = swr_convert(swr, output, outSamples,
                    const_cast<const uint8_t**>(frame->data), frame->nb_samples);
                if (converted > 0) {
                    auto* fltData = reinterpret_cast<float*>(output[0]);
                    allAudio.insert(allAudio.end(), fltData, fltData + converted * 2);
                }
                av_freep(&output[0]);
            }
        }
        av_packet_unref(packet);
    }

    av_frame_free(&frame);
    av_packet_free(&packet);
    swr_free(&swr);
    avcodec_free_context(&codecCtx);
    avformat_close_input(&fmtCtx);
    avformat_network_deinit();

    if (allAudio.empty()) return false;

    // Store decoded data
    {
        std::lock_guard lock(m_decodeMutex);
        m_decodedAudio = std::move(allAudio);
        m_sampleRate = 48000;
        m_numChannels = 2;
        m_readCursor = 0;
    }

    // Calculate actual duration
    if (durationSec <= 0 && !m_decodedAudio.empty()) {
        {
            std::lock_guard lock(m_decodeMutex);
            durationSec = static_cast<int>(m_decodedAudio.size() / (2 * 48000));
        }
    }
    m_duration.store(durationSec);
    emit durationChanged();

    return true;
}

void LocalMediaDeck::load(const QString& path) {
    stop();
    setFilePath(path);

    if (std::filesystem::exists(path.toStdString())) {
        if (decodeFile(path)) {
            return; // decoded OK
        }
    }

    // Decode failed — duration stays 0, UI shows "Load Failed"
    m_duration.store(0);
    emit durationChanged();
}

void LocalMediaDeck::updateTimerTick() {
    if (m_playing.load()) {
        int pos = m_position.load();
        int dur = m_duration.load();
        if (pos < dur) {
            m_position.store(pos + 1);
            emit positionChanged();
            emit playbackProgressChanged();
        } else {
            if (m_loop.load()) {
                m_position.store(0);
                std::lock_guard lock(m_decodeMutex);
                m_readCursor = 0;
                emit positionChanged();
                emit playbackProgressChanged();
            } else {
                setPlaying(false);
            }
        }
    }
}

void LocalMediaDeck::readPlaybackSamples(uint32_t patchIdx, float* destBuffer, size_t numSamples) noexcept {
    if (!m_playing.load(std::memory_order_relaxed)) {
        std::fill_n(destBuffer, numSamples, 0.0f);
        return;
    }

    double vol = m_volume.load(std::memory_order_relaxed);
    bool isLeft = (patchIdx % 2 == 0);

    std::lock_guard lock(m_decodeMutex);
    if (m_decodedAudio.empty()) {
        // No decoded audio — output silence
        std::fill_n(destBuffer, numSamples, 0.0f);
        return;
    }

    // Read from decoded ring buffer
    size_t samplesAvail = m_decodedAudio.size() / m_numChannels;
    size_t chOffset = isLeft ? 0 : 1;

    for (size_t s = 0; s < numSamples; ++s) {
        if (m_readCursor < samplesAvail) {
            destBuffer[s] = m_decodedAudio[m_readCursor * m_numChannels + chOffset] * static_cast<float>(vol);
            m_readCursor++;
        } else if (m_loop.load(std::memory_order_relaxed)) {
            m_readCursor = 0;
            destBuffer[s] = m_decodedAudio[chOffset] * static_cast<float>(vol);
            m_readCursor++;
        } else {
            destBuffer[s] = 0.0f;
        }
    }
}

void LocalMediaDeck::generateVideoFrame(QImage& image, int frameCount, int width, int height) {
    if (image.width() != width || image.height() != height || image.format() != QImage::Format_ARGB32) {
        image = QImage(width, height, QImage::Format_ARGB32);
    }

    image.fill(QColor("#0a0c10"));

    QPainter painter(&image);
    painter.setRenderHint(QPainter::Antialiasing);

    // Draw grid
    painter.setPen(QPen(QColor("#151b24"), 1));
    int gridSize = 40;
    for (int x = 0; x < width; x += gridSize) painter.drawLine(x, 0, x, height);
    for (int y = 0; y < height; y += gridSize) painter.drawLine(0, y, width, y);

    int posVal = m_position.load();
    int durVal = m_duration.load();
    double progress = durVal > 0 ? static_cast<double>(posVal) / durVal : 0.0;

    // Draw waveform from decoded audio
    painter.setPen(QPen(QColor("#00bdd6"), 2));
    int centerY = height / 2;

    if (!m_decodedAudio.empty()) {
        std::lock_guard lock(m_decodeMutex);
        size_t totalSamples = m_decodedAudio.size() / m_numChannels;
        if (totalSamples > 0) {
            QPainterPath path;
            path.moveTo(0, centerY);
            for (int x = 0; x < width; ++x) {
                size_t idx = static_cast<size_t>(x) * totalSamples / static_cast<size_t>(width);
                float sample = m_decodedAudio[std::min(idx * m_numChannels, m_decodedAudio.size() - 1)];
                float amp = sample * 100.0f;
                path.lineTo(x, centerY + static_cast<int>(amp));
            }
            painter.drawPath(path);
        }
    } else {
        // No media loaded — show "No Media" indicator
        painter.setPen(QColor("#666666"));
        QFont nf = painter.font(); nf.setBold(true); nf.setPixelSize(24); painter.setFont(nf);
        painter.drawText(image.rect(), Qt::AlignCenter, "NO MEDIA");
    }

    // Text overlays
    painter.setPen(QColor("#ffffff"));
    QFont font = painter.font();
    font.setFamily("Segoe UI");
    font.setBold(true);
    font.setPixelSize(20);
    painter.setFont(font);

    QString stateText = m_playing.load() ? "PLAYING" : "PAUSED";
    if (posVal == 0 && !m_playing.load()) stateText = "STOPPED";
    painter.drawText(20, 40, "MEDIA DECK: " + stateText);

    font.setBold(false);
    font.setPixelSize(14);
    painter.setFont(font);
    QString file;
    {
        std::lock_guard<std::mutex> fLock(m_fileMutex);
        file = m_filePath.isEmpty() ? "No File Loaded" : m_filePath;
    }
    painter.drawText(20, 70, "FILE: " + file);

    // Progress bar
    int barY = height - 50;
    int barW = width - 40;
    painter.fillRect(20, barY, barW, 8, QColor("#1a1c1e"));
    painter.fillRect(20, barY, static_cast<int>(barW * progress), 8, QColor("#00bdd6"));

    int min = posVal / 60, sec = posVal % 60;
    int durMin = durVal / 60, durSec = durVal % 60;
    QString timeStr = QString("%1:%2 / %3:%4")
        .arg(min, 2, 10, QChar('0')).arg(sec, 2, 10, QChar('0'))
        .arg(durMin, 2, 10, QChar('0')).arg(durSec, 2, 10, QChar('0'));
    painter.drawText(20, barY - 10, timeStr);
}