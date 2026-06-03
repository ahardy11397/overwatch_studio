#pragma once

#include <QQuickPaintedItem>
#include <QPainter>
#include <QTimer>
#include <array>
#include <QImage>


/**
 * @class VideoCanvasMock
 * @brief Serves as a placeholder for the native D3D11 zero-copy video renderer.
 */
class VideoCanvasMock : public QQuickPaintedItem {
    Q_OBJECT
    Q_PROPERTY(int programCamera READ programCamera WRITE setProgramCamera NOTIFY programCameraChanged)
    Q_PROPERTY(int previewCamera READ previewCamera WRITE setPreviewCamera NOTIFY previewCameraChanged)

public:
    explicit VideoCanvasMock(QQuickItem* parent = nullptr);
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

signals:
    void programCameraChanged();
    void previewCameraChanged();

private slots:
    void updateFrame();

private:
    QTimer* m_timer;
    int m_frameCount = 0;
    int m_programCamera = 0; // Default: Cam 1
    int m_previewCamera = 1; // Default: Cam 2
    std::array<QImage, 4> m_cameraImages;
};

