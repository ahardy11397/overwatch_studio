#ifndef NOMINMAX
#define NOMINMAX
#endif
#include "VideoCanvasMock.h"
#include "LocalMediaDeck.h"
#include "../core/control/PanicSwitch.h"
#include "../core/video/VideoEngineCore.h"
#include <QBrush>
#include <QColor>
#include <QPen>
#include <QCoreApplication>
#include <QDebug>
#include <QLinearGradient>
#include <wrl/client.h>

using Microsoft::WRL::ComPtr;

VideoCanvasMock::VideoCanvasMock(QQuickItem* parent)
    : QQuickPaintedItem(parent)
{
    m_timer = new QTimer(this);
    connect(m_timer, &QTimer::timeout, this, &VideoCanvasMock::updateFrame);
    m_timer->start(16); // 60fps

    // Load fallback camera images
    for (int i = 0; i < 4; ++i) {
        QString filename = QString("cam%1.png").arg(i + 1);
        QStringList searchPaths = {
            QCoreApplication::applicationDirPath() + "/assets/",
            QCoreApplication::applicationDirPath() + "/../src/ui/assets/",
            QCoreApplication::applicationDirPath() + "/../../src/ui/assets/",
            "./src/ui/assets/",
            "../src/ui/assets/"
        };
        for (const QString& path : searchPaths) {
            if (m_cameraImages[i].load(path + filename)) {
                qDebug() << "Loaded camera image" << filename << "from" << path;
                break;
            }
        }
    }

    // Set up D3D11 when we get a window
    connect(this, &QQuickItem::windowChanged, this, &VideoCanvasMock::onWindowChanged);
}

VideoCanvasMock::~VideoCanvasMock() {
    if (m_d3dCtx) m_d3dCtx->Release();
    if (m_d3dDevice) m_d3dDevice->Release();
}

void VideoCanvasMock::onWindowChanged(QQuickWindow* win) {
    if (win) {
        ensureD3D11();
    }
}

void VideoCanvasMock::ensureD3D11() {
    if (m_d3dDevice) return;

    // Create a D3D11 device for readback
    // If the app already has a device, share it; otherwise create one
    D3D_FEATURE_LEVEL featureLevel;
    HRESULT hr = D3D11CreateDevice(
        nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr,
        D3D11_CREATE_DEVICE_BGRA_SUPPORT,
        nullptr, 0, D3D11_SDK_VERSION,
        &m_d3dDevice, &featureLevel, &m_d3dCtx);
    if (FAILED(hr)) {
        qDebug() << "VideoCanvasMock: failed to create D3D11 device for readback";
    }
}

void VideoCanvasMock::readTexture(QImage& outImage) {
    ID3D11Texture2D* srcTex = g_videoOutputTexture.load(std::memory_order_acquire);
    if (!m_d3dDevice || !m_d3dCtx || !srcTex) return;
    D3D11_TEXTURE2D_DESC desc;
    srcTex->GetDesc(&desc);

    // Create a staging texture for CPU readback
    D3D11_TEXTURE2D_DESC stagingDesc = {};
    stagingDesc.Width = desc.Width;
    stagingDesc.Height = desc.Height;
    stagingDesc.MipLevels = 1;
    stagingDesc.ArraySize = 1;
    stagingDesc.Format = OutputFormat;
    stagingDesc.SampleDesc.Count = 1;
    stagingDesc.Usage = D3D11_USAGE_STAGING;
    stagingDesc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;

    ComPtr<ID3D11Texture2D> stagingTex;
    HRESULT hr = m_d3dDevice->CreateTexture2D(&stagingDesc, nullptr, &stagingTex);
    if (FAILED(hr)) return;

    m_d3dCtx->CopyResource(stagingTex.Get(), srcTex);

    D3D11_MAPPED_SUBRESOURCE mapped;
    hr = m_d3dCtx->Map(stagingTex.Get(), 0, D3D11_MAP_READ, 0, &mapped);
    if (FAILED(hr)) return;

    // Create QImage from the mapped data
    QImage img(static_cast<int>(desc.Width), static_cast<int>(desc.Height),
               QImage::Format_ARGB32_Premultiplied);
    const auto* src = static_cast<const uint8_t*>(mapped.pData);
    for (UINT y = 0; y < desc.Height; ++y) {
        memcpy(img.scanLine(static_cast<int>(y)),
               src + y * mapped.RowPitch,
               desc.Width * 4);
    }

    m_d3dCtx->Unmap(stagingTex.Get(), 0);
    outImage = img;
}

void VideoCanvasMock::paint(QPainter* painter) {
    QRectF r = boundingRect();

    if (PanicSwitch::getInstance().isFadeToBlackActive()) {
        painter->fillRect(r, QBrush(QColor("#000000")));
        painter->setPen(QColor("#ff3b30"));
        QFont f = painter->font(); f.setBold(true); f.setPixelSize(16); painter->setFont(f);
        painter->drawText(r, Qt::AlignCenter, "FADE TO BLACK ACTIVE\n[PANIC BLACKOUT ENGAGED]");
        return;
    }

    qreal w = r.width(), h = r.height();
    qreal halfW = w / 2.0, halfH = h / 2.0;
    std::array<QRectF, 4> rects = {
        QRectF(0, 0, halfW, halfH),
        QRectF(halfW, 0, halfW, halfH),
        QRectF(0, halfH, halfW, halfH),
        QRectF(halfW, halfH, halfW, halfH)
    };

    for (int i = 0; i < 4; ++i) {
        QRectF qr = rects[i];

        // Try to paint a real frame from the pipeline
        if (!m_channelFrames[i].isNull()) {
            painter->drawImage(qr, m_channelFrames[i]);
            painter->fillRect(qr, QBrush(QColor(0, 0, 0, 80))); // dim overlay
        } else if (!m_cameraImages[i].isNull()) {
            painter->drawImage(qr, m_cameraImages[i]);
            painter->fillRect(qr, QBrush(QColor(0, 0, 0, 100)));
        } else {
            QLinearGradient grad(qr.topLeft(), qr.bottomRight());
            grad.setColorAt(0.0, QColor("#141923"));
            grad.setColorAt(1.0, QColor("#090b0f"));
            painter->fillRect(qr, grad);
            painter->fillRect(qr, QBrush(QColor(0, 0, 0, 50)));
        }

        // Camera label
        painter->setPen(QColor("#ffffff"));
        QFont lf = painter->font(); lf.setBold(true); lf.setPixelSize(11); painter->setFont(lf);
        painter->drawText(qr.adjusted(12, 12, -12, -12), Qt::AlignTop | Qt::AlignLeft,
                          QString("CAMERA %1").arg(i + 1));

        // Specs
        painter->setPen(QColor("#a1a1aa"));
        QFont sf = painter->font(); sf.setBold(false); sf.setPixelSize(8); painter->setFont(sf);
        painter->drawText(qr.adjusted(12, 12, -12, -12), Qt::AlignBottom | Qt::AlignRight,
                          "1080p60 | GPU-SYNC");
    }

    // PGM scanner line
    if (m_programCamera >= 0 && m_programCamera < 4) {
        QRectF pr = rects[m_programCamera];
        int scanY = (m_frameCount * 3) % static_cast<int>(pr.height());
        painter->setPen(QPen(QColor("#ff3b30"), 2));
        painter->drawLine(pr.left(), pr.top() + scanY, pr.right(), pr.top() + scanY);
    }

    // PGM (red) and PVW (green) borders
    if (m_previewCamera >= 0 && m_previewCamera < 4) {
        QRectF pv = rects[m_previewCamera];
        painter->setPen(QPen(QColor("#30d158"), 4));
        painter->drawRect(pv.adjusted(2, 2, -2, -2));
    }
    if (m_programCamera >= 0 && m_programCamera < 4) {
        QRectF pg = rects[m_programCamera];
        painter->setPen(QPen(QColor("#ff3b30"), 4));
        painter->drawRect(pg.adjusted(2, 2, -2, -2));
    }

    // Grid lines
    painter->setPen(QPen(QColor("#252b36"), 2));
    painter->drawLine(halfW, 0, halfW, h);
    painter->drawLine(0, halfH, w, halfH);

    // Media Deck PiP overlay
    if (m_mediaDeck != nullptr && (m_programCamera == 4 || m_previewCamera == 4)) {
        QRectF mediaRect(halfW - 120, h - 110, 240, 100);
        QImage mediaFrame;
        m_mediaDeck->generateVideoFrame(mediaFrame, m_frameCount, 240, 100);
        painter->drawImage(mediaRect, mediaFrame);
        painter->setPen(QPen(m_programCamera == 4 ? QColor("#ff3b30") : QColor("#30d158"), 3));
        painter->drawRect(mediaRect);
        painter->setPen(QColor("#ffffff"));
        QFont lf = painter->font(); lf.setBold(true); lf.setPixelSize(10); painter->setFont(lf);
        painter->drawText(mediaRect.adjusted(8, 8, -8, -8), Qt::AlignTop | Qt::AlignLeft, "MEDIA DECK OUT");
    }
}

void VideoCanvasMock::setMediaDeck(LocalMediaDeck* deck) {
    if (m_mediaDeck != deck) {
        m_mediaDeck = deck;
        emit mediaDeckChanged();
        update();
    }
}

void VideoCanvasMock::updateFrame() {
    m_frameCount++;

    // Read back the latest composited frame from the video pipeline
    ensureD3D11();
    ID3D11Texture2D* outputTex = g_videoOutputTexture.load(std::memory_order_acquire);
    if (outputTex) {
        QImage frame;
        readTexture(frame);
        if (!frame.isNull()) {
            m_channelFrames[m_programCamera] = frame;
        }
    }

    update();
}