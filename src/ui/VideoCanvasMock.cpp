#include "VideoCanvasMock.h"
#include "LocalMediaDeck.h"
#include "../core/control/PanicSwitch.h"
#include <QBrush>
#include <QColor>
#include <QPen>
#include <array>
#include <cmath>
#include <QCoreApplication>
#include <QDebug>
#include <QLinearGradient>

VideoCanvasMock::VideoCanvasMock(QQuickItem* parent) : QQuickPaintedItem(parent) {
    m_timer = new QTimer(this);
    connect(m_timer, &QTimer::timeout, this, &VideoCanvasMock::updateFrame);
    m_timer->start(16); // 60fps mock genlock rendering

    for (int i = 0; i < 4; ++i) {
        QString filename = QString("cam%1.png").arg(i + 1);
        bool loaded = false;

        QStringList searchPaths = {
            QCoreApplication::applicationDirPath() + "/assets/",
            QCoreApplication::applicationDirPath() + "/../src/ui/assets/",
            QCoreApplication::applicationDirPath() + "/../../src/ui/assets/",
            "./src/ui/assets/",
            "../src/ui/assets/"
        };

        for (const QString& path : searchPaths) {
            QString fullPath = path + filename;
            if (m_cameraImages[i].load(fullPath)) {
                qDebug() << "Successfully loaded camera image" << filename << "from" << fullPath;
                loaded = true;
                break;
            }
        }

        if (!loaded) {
            qDebug() << "Failed to load camera image" << filename << "from any search paths.";
        }
    }
}


void VideoCanvasMock::paint(QPainter* painter) {
    if (PanicSwitch::getInstance().isFadeToBlackActive()) {
        painter->fillRect(boundingRect(), QBrush(QColor("#000000")));
        
        painter->setPen(QColor("#ff3b30"));
        QFont font = painter->font();
        font.setBold(true);
        font.setPixelSize(16);
        painter->setFont(font);
        painter->drawText(boundingRect(), Qt::AlignCenter, "FADE TO BLACK ACTIVE\n[PANIC BLACKOUT ENGAGED]");
        return;
    }

    qreal w = boundingRect().width();
    qreal h = boundingRect().height();
    qreal halfW = w / 2.0;
    qreal halfH = h / 2.0;

    std::array<QRectF, 4> rects = {
        QRectF(0, 0, halfW, halfH),
        QRectF(halfW, 0, halfW, halfH),
        QRectF(0, halfH, halfW, halfH),
        QRectF(halfW, halfH, halfW, halfH)
    };

    // Draw background/camera feed and high-tech wireframe for all quadrants
    for (int i = 0; i < 4; ++i) {
        QRectF r = rects[i];

        // 1. Paint camera feed if available, or fallback gradient
        if (!m_cameraImages[i].isNull()) {
            painter->drawImage(r, m_cameraImages[i]);
            // Paint dark overlay with alpha to make overlays readable
            painter->fillRect(r, QBrush(QColor(0, 0, 0, 100)));
        } else {
            // Draw a beautiful technical fallback gradient (from #141923 to #090b0f)
            QLinearGradient gradient(r.topLeft(), r.bottomRight());
            gradient.setColorAt(0.0, QColor("#141923"));
            gradient.setColorAt(1.0, QColor("#090b0f"));
            painter->fillRect(r, QBrush(gradient));

            // Paint dark overlay with alpha to make text pop
            painter->fillRect(r, QBrush(QColor(0, 0, 0, 50)));
        }

        // Camera labels (white/light gray)
        painter->setPen(QColor("#ffffff"));
        QFont labelFont = painter->font();
        labelFont.setBold(true);
        labelFont.setPixelSize(11);
        painter->setFont(labelFont);
        QString label = QString("CAMERA %1").arg(i + 1);
        painter->drawText(r.adjusted(12, 12, -12, -12), Qt::AlignTop | Qt::AlignLeft, label);

        // Technical specs overlay
        painter->setPen(QColor("#a1a1aa")); // light gray
        QFont infoFont = painter->font();
        infoFont.setBold(false);
        infoFont.setPixelSize(8);
        painter->setFont(infoFont);
        painter->drawText(r.adjusted(12, 12, -12, -12), Qt::AlignBottom | Qt::AlignRight, "1080p60 | GPU-SYNC");
    }

    // 1. Draw Program scanning line inside Program camera's quadrant
    if (m_programCamera >= 0 && m_programCamera < 4) {
        QRectF progRect = rects[m_programCamera];
        int scanYOffset = (m_frameCount * 3) % static_cast<int>(progRect.height());
        qreal lineY = progRect.top() + scanYOffset;
        painter->setPen(QPen(QColor("#ff3b30"), 2)); // Red scanner line
        painter->drawLine(progRect.left(), lineY, progRect.right(), lineY);
    }

    // 2. Draw active borders around Preview (green) and Program (red)
    if (m_previewCamera >= 0 && m_previewCamera < 4) {
        QRectF prevRect = rects[m_previewCamera];
        painter->setPen(QPen(QColor("#30d158"), 4)); // Bright green PVW border
        painter->drawRect(prevRect.adjusted(2, 2, -2, -2));
    }
    if (m_programCamera >= 0 && m_programCamera < 4) {
        QRectF progRect = rects[m_programCamera];
        painter->setPen(QPen(QColor("#ff3b30"), 4)); // Bright red PGM border
        painter->drawRect(progRect.adjusted(2, 2, -2, -2));
    }

    // 3. Draw grid divider lines to separate quadrants beautifully
    painter->setPen(QPen(QColor("#252b36"), 2));
    painter->drawLine(halfW, 0, halfW, h);
    painter->drawLine(0, halfH, w, halfH);

    // 4. Draw floating PiP monitor for Media Deck Out
    if (m_mediaDeck != nullptr && (m_programCamera == 4 || m_previewCamera == 4)) {
        QRectF mediaRect(halfW - 120, h - 110, 240, 100);
        
        // Generate frame
        QImage mediaFrame;
        m_mediaDeck->generateVideoFrame(mediaFrame, m_frameCount, 240, 100);
        painter->drawImage(mediaRect, mediaFrame);
        
        // Draw border based on selected PGM/PVW
        if (m_programCamera == 4) {
            painter->setPen(QPen(QColor("#ff3b30"), 3)); // Red PGM
        } else {
            painter->setPen(QPen(QColor("#30d158"), 3)); // Green PVW
        }
        painter->drawRect(mediaRect);
        
        // Label
        painter->setPen(QColor("#ffffff"));
        QFont labelFont = painter->font();
        labelFont.setBold(true);
        labelFont.setPixelSize(10);
        painter->setFont(labelFont);
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
    update(); // Triggers a repaint
}
