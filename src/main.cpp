#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QMessageLogContext>
#include <QString>
#include <QFile>
#include <QQuickStyle>
#include "ui/AudioEngineBridge.h"
#include "ui/VideoCanvasMock.h"
#include "ui/ShowBuilderBridge.h"
#include "ui/LocalMediaDeck.h"
#include "core/control/RealtimeLogger.h"
#include "core/control/SystemWatchdog.h"
#include "core/control/ResourceShedder.h"

void qtMessageHandler(QtMsgType type, const QMessageLogContext &context, const QString &msg) {
    std::string levelPrefix;
    switch (type) {
        case QtDebugMsg: levelPrefix = "[QT DEBUG] "; break;
        case QtInfoMsg: levelPrefix = "[QT INFO] "; break;
        case QtWarningMsg: levelPrefix = "[QT WARNING] "; break;
        case QtCriticalMsg: levelPrefix = "[QT CRITICAL] "; break;
        case QtFatalMsg: levelPrefix = "[QT FATAL] "; break;
    }
    std::string fullMsg = levelPrefix + msg.toStdString();
    if (context.file) {
        fullMsg += " (" + std::string(context.file) + ":" + std::to_string(context.line) + ")";
    }
    RealtimeLogger::getInstance().log(fullMsg);
}

int main(int argc, char *argv[]) {
    QQuickStyle::setStyle("Basic");
    RealtimeLogger::getInstance().start("F:/Drive/scripts/overwatch_studio/overwatch_studio_realtime.log");
    qInstallMessageHandler(qtMessageHandler);
    
    QGuiApplication app(argc, argv);

    RealtimeLogger::getInstance().log("OVERWATCH STUDIO SYSTEM ENGINE STARTUP SEQUENCE INITIATED...");

    SystemWatchdog::getInstance().setSheddingCallback([](int level) {
        ResourceShedder::getInstance().setSheddingLevel(level);
    });

    qmlRegisterType<AudioEngineBridge>("Overwatch.Core", 1, 0, "AudioEngineBridge");
    qmlRegisterType<VideoCanvasMock>("Overwatch.Core", 1, 0, "VideoCanvasMock");
    qmlRegisterType<ShowBuilderBridge>("Overwatch.Core", 1, 0, "ShowBuilderBridge");
    qmlRegisterUncreatableType<LocalMediaDeck>("Overwatch.Core", 1, 0, "LocalMediaDeck", "Cannot instantiate LocalMediaDeck directly");

    QQmlApplicationEngine engine;
    engine.addImportPath("qrc:/");
    engine.addImportPath("qrc:/qt/qml/");

    QString localPath = "F:/Drive/scripts/overwatch_studio/src/ui/Main.qml";
    QUrl url;
    if (QFile::exists(localPath)) {
        url = QUrl::fromLocalFile(localPath);
        RealtimeLogger::getInstance().log("Found local Main.qml. Loading from filesystem: " + url.toString().toStdString());
    } else {
        url = QUrl(u"qrc:/qt/qml/overwatch_studio/src/ui/Main.qml"_qs);
        RealtimeLogger::getInstance().log("Local Main.qml not found. Loading from QRC: " + url.toString().toStdString());
    }

    QObject::connect(&engine, &QQmlApplicationEngine::objectCreated,
        &app, [url](QObject *obj, const QUrl &objUrl) {
            if (!obj) {
                RealtimeLogger::getInstance().log("FATAL: QQmlApplicationEngine failed to create QML object for URL: " + objUrl.toString().toStdString());
                QCoreApplication::exit(-1);
            } else {
                RealtimeLogger::getInstance().log("SUCCESS: QML object created successfully for URL: " + objUrl.toString().toStdString());
            }
        }, Qt::QueuedConnection);
    
    engine.load(url);

    int result = app.exec();

    // Shutdown background watchdog and logger threads safely before exit
    SystemWatchdog::getInstance().stop();
    RealtimeLogger::getInstance().stop();

    return result;
}
