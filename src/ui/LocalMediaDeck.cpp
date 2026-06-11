#include "LocalMediaDeck.h"
#include <QTimer>
#include <QPainter>
#include <QPainterPath>
#include <QColor>
#include <QPen>
#include <QFont>
#include <cmath>
#include <algorithm>

LocalMediaDeck::LocalMediaDeck(QObject* parent) : QObject(parent) {
    m_tickTimer = new QTimer(this);
    connect(m_tickTimer, &QTimer::timeout, this, &LocalMediaDeck::updateTimerTick);
    m_tickTimer->start(1000); // Trigger tick every second
}

LocalMediaDeck::~LocalMediaDeck() {
    m_tickTimer->stop();
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

void LocalMediaDeck::load(const QString& path) {
    stop();
    setFilePath(path);
    // Mock duration parsing: set different durations based on file name length
    int dur = 60 + (path.length() * 3) % 180;
    m_duration.store(dur);
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

    // Generate a rich polyphonic synth texture using a C major chord
    const double freqs[4] = { 130.81, 164.81, 196.00, 246.94 }; // C3, E3, G3, B3
    double& phase = isLeft ? m_phaseL : m_phaseR;

    for (size_t s = 0; s < numSamples; ++s) {
        double sum = 0.0;
        for (int i = 0; i < 4; ++i) {
            double freq = freqs[i] * (isLeft ? 1.0 : 1.002); // slight detuning for width
            sum += std::sin(phase + i * 1.5);
        }
        sum *= 0.25;

        // Apply filter sweep using LFO
        double t = static_cast<double>(m_position.load()) + static_cast<double>(s) / 48000.0;
        double lfo = 0.6 + 0.4 * std::sin(2.0 * 3.14159265 * 0.25 * t); // 0.25Hz LFO
        
        destBuffer[s] = static_cast<float>(sum * vol * lfo);

        phase += 2.0 * 3.14159265 * 130.81 / 48000.0;
        if (phase >= 2.0 * 3.14159265) phase -= 2.0 * 3.14159265;
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
    for (int x = 0; x < width; x += gridSize) {
        painter.drawLine(x, 0, x, height);
    }
    for (int y = 0; y < height; y += gridSize) {
        painter.drawLine(0, y, width, y);
    }

    int posVal = m_position.load();
    int durVal = m_duration.load();
    double progress = durVal > 0 ? static_cast<double>(posVal) / durVal : 0.0;

    // Draw dynamic visual waves
    painter.setPen(QPen(QColor("#00bdd6"), 2));
    int centerY = height / 2;
    int waveHeight = 60;
    QPainterPath path;
    path.moveTo(0, centerY);
    for (int x = 0; x < width; ++x) {
        double wavePhase = static_cast<double>(x) * 0.05 + (m_playing.load() ? static_cast<double>(frameCount) * 0.2 : 0.0);
        double amp = std::sin(wavePhase) * std::cos(wavePhase * 0.3);
        double val = centerY + amp * waveHeight * (m_playing.load() ? 1.0 : 0.1);
        path.lineTo(x, val);
    }
    painter.drawPath(path);

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
        std::lock_guard<std::mutex> lock(m_fileMutex);
        file = m_filePath.isEmpty() ? "No File Loaded" : m_filePath;
    }
    painter.drawText(20, 70, "FILE: " + file);

    // Progress bar
    int barY = height - 50;
    int barW = width - 40;
    painter.fillRect(20, barY, barW, 8, QColor("#1a1c1e"));
    painter.fillRect(20, barY, static_cast<int>(barW * progress), 8, QColor("#00bdd6"));

    // Timecode string
    int min = posVal / 60;
    int sec = posVal % 60;
    int durMin = durVal / 60;
    int durSec = durVal % 60;
    QString timeStr = QString("%1:%2 / %3:%4")
        .arg(min, 2, 10, QChar('0'))
        .arg(sec, 2, 10, QChar('0'))
        .arg(durMin, 2, 10, QChar('0'))
        .arg(durSec, 2, 10, QChar('0'));
    painter.drawText(20, barY - 10, timeStr);
}
