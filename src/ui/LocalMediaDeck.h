#pragma once
#include <QObject>
#include <QString>
#include <QImage>
#include <atomic>
#include <mutex>
#include <vector>
#include <cstdint>

class LocalMediaDeck : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool playing READ isPlaying WRITE setPlaying NOTIFY playingChanged)
    Q_PROPERTY(int duration READ duration NOTIFY durationChanged)
    Q_PROPERTY(int position READ position WRITE setPosition NOTIFY positionChanged)
    Q_PROPERTY(QString filePath READ filePath WRITE setFilePath NOTIFY filePathChanged)
    Q_PROPERTY(double volume READ volume WRITE setVolume NOTIFY volumeChanged)
    Q_PROPERTY(bool loop READ loop WRITE setLoop NOTIFY loopChanged)
    Q_PROPERTY(double playbackProgress READ playbackProgress NOTIFY playbackProgressChanged)

public:
    explicit LocalMediaDeck(QObject* parent = nullptr);
    ~LocalMediaDeck();

    bool isPlaying() const { return m_playing.load(std::memory_order_relaxed); }
    void setPlaying(bool play);

    int duration() const { return m_duration.load(std::memory_order_relaxed); }
    int position() const { return m_position.load(std::memory_order_relaxed); }
    void setPosition(int pos);

    QString filePath() const;
    void setFilePath(const QString& path);

    double volume() const { return m_volume.load(std::memory_order_relaxed); }
    void setVolume(double vol);

    bool loop() const { return m_loop.load(std::memory_order_relaxed); }
    void setLoop(bool lp);

    double playbackProgress() const;

    Q_INVOKABLE void play();
    Q_INVOKABLE void pause();
    Q_INVOKABLE void stop();
    Q_INVOKABLE void load(const QString& path);

    // Real-time audio callback (lock-free, reads from decoded ring buffer)
    void readPlaybackSamples(uint32_t patchIdx, float* destBuffer, size_t numSamples) noexcept;

    // Video canvas frame painter (invoked by VideoCanvasMock)
    void generateVideoFrame(QImage& image, int frameCount, int width, int height);

signals:
    void playingChanged();
    void durationChanged();
    void positionChanged();
    void filePathChanged();
    void volumeChanged();
    void loopChanged();
    void playbackProgressChanged();

private:
    void updateTimerTick();
    bool decodeFile(const QString& path);
    void clearDecoded();

    std::atomic<bool> m_playing{false};
    std::atomic<int> m_duration{0};
    std::atomic<int> m_position{0};
    std::atomic<double> m_volume{1.0};
    std::atomic<bool> m_loop{true};

    mutable std::mutex m_fileMutex;
    QString m_filePath;

    class QTimer* m_tickTimer = nullptr;

    // Decoded audio data and state
    // ponytail: full-file decode, stream decode when file sizes exceed 100MB
    std::mutex m_decodeMutex;
    std::vector<float> m_decodedAudio; // interleaved stereo float samples
    int m_sampleRate = 48000;
    int m_numChannels = 2;
    size_t m_readCursor = 0; // sample index (per channel), not guarded by mutex
};
