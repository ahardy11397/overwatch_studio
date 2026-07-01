#pragma once

#include <QObject>
#include <QRect>
#include <QSettings>
#include <QScreen>
#include <QGuiApplication>
#include <QString>

/**
 * WindowStateStore
 * Handle geometry and state persistence for multiple windows in Overwatch Studio.
 */
class WindowStateStore : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString organization READ organization WRITE setOrganization NOTIFY organizationChanged)
    Q_PROPERTY(QString application READ application WRITE setApplication NOTIFY applicationChanged)

public:
    explicit WindowStateStore(QObject* parent = nullptr)
        : QObject(parent), m_settings("Antigravity AI", "Overwatch Studio") {}

    Q_INVOKABLE void saveWindowGeometry(const QString& windowName, const QRect& geometry, int screenIndex) {
        m_settings.beginGroup(windowName);
        m_settings.setValue("geometry", geometry);
        m_settings.setValue("screen", screenIndex);
        m_settings.endGroup();
        m_settings.sync();
    }

    Q_INVOKABLE QRect restoreWindowGeometry(const QString& windowName, const QRect& defaultGeometry) {
        m_settings.beginGroup(windowName);
        QRect rect = m_settings.value("geometry", defaultGeometry).toRect();
        m_settings.endGroup();
        return rect;
    }

    Q_INVOKABLE int restoreWindowScreen(const QString& windowName, int defaultScreen = 0) {
        m_settings.beginGroup(windowName);
        int screen = m_settings.value("screen", defaultScreen).toInt();
        m_settings.endGroup();

        if (screen >= QGuiApplication::screens().size()) {
            return 0;
        }
        return screen;
    }

    QString organization() const { return m_settings.organizationName(); }
    void setOrganization(const QString& org) {
        if (m_settings.organizationName() != org) {
            // QSettings doesn't allow changing org after creation easily without re-instantiating,
            // but for our purposes this is fine as we use defaults.
            emit organizationChanged();
        }
    }

    QString application() const { return m_settings.applicationName(); }
    void setApplication(const QString& app) {
        if (m_settings.applicationName() != app) {
            emit applicationChanged();
        }
    }

signals:
    void organizationChanged();
    void applicationChanged();

private:
    QSettings m_settings;
};
