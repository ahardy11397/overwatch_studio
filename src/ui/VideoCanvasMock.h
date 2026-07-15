#pragma once

#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <QQuickPaintedItem>
#include <QPainter>
#include <QTimer>
#include <QImage>
#include <QQuickWindow>
#include <array>
#include <atomic>
#include <d3d11.h>
#include <wrl/client.h>
#include "LocalMediaDeck.h"

/**
 * @class VideoCanvas
 *
 * QQuickPaintedItem that renders composited video frames from the D3D11 pipeline.
 * - Reads a shared D3D11 texture via staging copy each frame
 * - Overlays PGM/PVW borders and camera labels with QPainter
 * - Shares D3D11 device with the video pipeline (no separate device)
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

    /// Share D3D11 device with video pipeline (call before first frame)
    void setSharedDevice(ID3D11Device* device, ID3D11DeviceContext* ctx);

    /// Static: set shared device for all VideoCanvas instances
    static void setGlobalSharedDevice(ID3D11Device* device, ID3D11DeviceContext* ctx);

    
signals:
    void programCameraChanged();
    void previewCameraChanged();
    void mediaDeckChanged();

private slots:
    void updateFrame();
    void onWindowChanged(QQuickWindow* win);

private:
    void readTexture(QImage& outImage);
    void ensureStagingTexture(UINT width, UINT height);

    QTimer* m_timer;
    int m_frameCount = 0;
    int m_programCamera = 0;
    int m_previewCamera = 1;
    std::array<QImage, 4> m_channelFrames; // real frames from pipeline
    LocalMediaDeck* m_mediaDeck = nullptr;

    // D3D11 interop — shared device from video pipeline
    ID3D11Device* m_d3dDevice = nullptr;
    ID3D11DeviceContext* m_d3dCtx = nullptr;
    bool m_ownsDevice = false; // true if we created the device (fallback)

    // Cached staging texture (reused across frames, only recreated on resize)
    Microsoft::WRL::ComPtr<ID3D11Texture2D> m_stagingTex;
    UINT m_stagingWidth = 0;
    UINT m_stagingHeight = 0;

    static constexpr DXGI_FORMAT OutputFormat = DXGI_FORMAT_B8G8R8A8_UNORM;

    // Global shared device (set by main.cpp, used by all instances)
    static inline ID3D11Device* s_sharedDevice = nullptr;
    static inline ID3D11DeviceContext* s_sharedCtx = nullptr;
};