#pragma once

#include <QQuickPaintedItem>
#include <QPainter>
#include <QTimer>
#include <QImage>
#include <QQuickWindow>
#include <array>
#include <atomic>
#include <d3d11.h>
#include "LocalMediaDeck.h"

/**
 * @class VideoCanvasMock → RealD3D11Canvas (beta hybrid)
 *
 * QQuickPaintedItem that renders composited video frames.
 * - Reads a shared D3D11 texture from the capture pipeline each frame
 * - Falls back to mock camera images if no real texture is available
 * - Maintains the PGM/PVW border overlay UX
 */
class VideoCanvasMock : public QQuickPaintedItem {
    Q_OBJECT
    Q_PROPERTY(int programCamera READ programCamera WRITE setProgramCamera NOTIFY programCameraChanged)
    Q_PROPERTY(int previewCamera READ previewCamera WRITE setPreviewCamera NOTIFY previewCameraChanged)
    Q_PROPERTY(LocalMediaDeck* mediaDeck READ mediaDeck WRITE setMediaDeck NOTIFY mediaDeckChanged)

public:
    explicit VideoCanvasMock(QQuickItem* parent = nullptr);
    ~VideoCanvasMock() override;
    void paint(QPainter* painter) override;

    int programCamera() const { return m_programCamera; }
    void setProgramCamera(int cam) {
        if (m_programCamera != cam) {
            m_programCamera = cam;
            emit programCameraChanged();
            update();
        }
    }

    int previewCamera() const { return m_previewCamera; }
    void setPreviewCamera(int cam) {
        if (m_previewCamera != cam) {
            m_previewCamera = cam;
            emit previewCameraChanged();
            update();
        }
    }

    LocalMediaDeck* mediaDeck() const { return m_mediaDeck; }
    void setMediaDeck(LocalMediaDeck* deck);

    
signals:
    void programCameraChanged();
    void previewCameraChanged();
    void mediaDeckChanged();

private slots:
    void updateFrame();
    void onWindowChanged(QQuickWindow* win);

private:
    void readTexture(QImage& outImage);
    void ensureD3D11();

    QTimer* m_timer;
    int m_frameCount = 0;
    int m_programCamera = 0;
    int m_previewCamera = 1;
    std::array<QImage, 4> m_cameraImages;
    std::array<QImage, 4> m_channelFrames; // real frames from pipeline
    LocalMediaDeck* m_mediaDeck = nullptr;

    // D3D11 interop
    ID3D11Device* m_d3dDevice = nullptr;
    ID3D11DeviceContext* m_d3dCtx = nullptr;

    static constexpr DXGI_FORMAT OutputFormat = DXGI_FORMAT_B8G8R8A8_UNORM;
};