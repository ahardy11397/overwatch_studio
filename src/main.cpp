#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QMessageLogContext>
#include <QString>
#include <QFile>
#include <QQuickStyle>
#include <QWindow>
#include "ui/AudioEngineBridge.h"
#include "ui/VideoCanvasMock.h"
#include "ui/ShowBuilderBridge.h"
#include "ui/LocalMediaDeck.h"
#include "core/control/RealtimeLogger.h"
#include "core/control/SystemWatchdog.h"
#include "core/control/ResourceShedder.h"
#include "core/control/WindowStateStore.h"
#include "core/control/ShowfileManager.h"
#include "core/video/VideoCaptureManager.h"
#include "core/video/VideoEngineCore.h"
#include <filesystem>
#include <vector>

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

    // Bootstrapping: Ensure default showfile exists
    std::filesystem::path assetsDir = "F:/Drive/scripts/overwatch_studio/assets/shows";
    if (!std::filesystem::exists(assetsDir)) {
        std::filesystem::create_directories(assetsDir);
    }
    std::filesystem::path defaultShow = assetsDir / "default.sds";
    if (!std::filesystem::exists(defaultShow)) {
        ShowfileManager sfm;
        if (sfm.createDefaultShowfile(defaultShow.string())) {
            RealtimeLogger::getInstance().log("Generated default.sds successfully.");
        } else {
            RealtimeLogger::getInstance().log("ERROR: Failed to generate default.sds.");
        }
    }

    QGuiApplication app(argc, argv);

    RealtimeLogger::getInstance().log("OVERWATCH STUDIO SYSTEM ENGINE STARTUP SEQUENCE INITIATED...");

    SystemWatchdog::getInstance().setSheddingCallback([](int level) {
        ResourceShedder::getInstance().setSheddingLevel(level);
    });

    qmlRegisterType<AudioEngineBridge>("Overwatch.Core", 1, 0, "AudioEngineBridge");
    qmlRegisterType<VideoCanvasMock>("Overwatch.Core", 1, 0, "VideoCanvasMock");
    qmlRegisterType<ShowBuilderBridge>("Overwatch.Core", 1, 0, "ShowBuilderBridge");
    qmlRegisterType<WindowStateStore>("Overwatch.Core", 1, 0, "WindowStateStore");
    qmlRegisterUncreatableType<LocalMediaDeck>("Overwatch.Core", 1, 0, "LocalMediaDeck", "Cannot instantiate LocalMediaDeck directly");

    // Shared bridges — one instance per service, shared across all windows via context properties
    AudioEngineBridge audioBridge;
    ShowBuilderBridge showBuilderBridge;

    struct WindowDef {
        const char* name;
        const char* localPath;
        const char* qrcPath;
    };
    const WindowDef windows[] = {
        {"MasterLauncher", "F:/Drive/scripts/overwatch_studio/src/ui/MasterLauncher.qml", "qrc:/qt/qml/overwatch_studio/src/ui/MasterLauncher.qml"},
        {"AudioConsole",   "F:/Drive/scripts/overwatch_studio/src/ui/AudioConsole.qml",   "qrc:/qt/qml/overwatch_studio/src/ui/AudioConsole.qml"},
        {"VideoSwitcher",  "F:/Drive/scripts/overwatch_studio/src/ui/VideoSwitcher.qml",  "qrc:/qt/qml/overwatch_studio/src/ui/VideoSwitcher.qml"},
        {"ShowBuilder",    "F:/Drive/scripts/overwatch_studio/src/ui/ShowBuilder.qml",    "qrc:/qt/qml/overwatch_studio/src/ui/ShowBuilder.qml"},
    };

    std::vector<QQmlApplicationEngine*> engines;
    for (const auto& w : windows) {
        auto* eng = new QQmlApplicationEngine(&app);
        eng->rootContext()->setContextProperty("audioCore", &audioBridge);
        eng->rootContext()->setContextProperty("showBuilder", &showBuilderBridge);
        eng->addImportPath("qrc:/");
        eng->addImportPath("qrc:/qt/qml/");

        QString localPath = QString::fromLatin1(w.localPath);
        QUrl url;
        if (QFile::exists(localPath)) {
            url = QUrl::fromLocalFile(localPath);
        } else {
            url = QUrl(QString::fromLatin1(w.qrcPath));
        }
        RealtimeLogger::getInstance().log(std::string("Loading ") + w.name + ": " + url.toString().toStdString());

        QObject::connect(eng, &QQmlApplicationEngine::objectCreated,
            &app, [w, url](QObject *obj, const QUrl &objUrl) {
                if (!obj) {
                    RealtimeLogger::getInstance().log(std::string("FATAL: ") + w.name + " failed to load: " + objUrl.toString().toStdString());
                } else {
                    RealtimeLogger::getInstance().log(std::string("SUCCESS: ") + w.name + " loaded.");
                }
            }, Qt::QueuedConnection);

        eng->load(url);
        engines.push_back(eng);
    }

    // After all windows loaded, start video capture
    // Find the VideoSwitcher window and get its HWND for WGC capture
    for (auto* eng : engines) {
        const auto roots = eng->rootObjects();
        if (roots.isEmpty()) continue;
        // Find which engine loaded VideoSwitcher by checking title
        auto* qmlWin = qobject_cast<QWindow*>(roots.first());
        if (qmlWin && qmlWin->title().contains("Video Switcher")) {
            HWND hwnd = reinterpret_cast<HWND>(qmlWin->winId());
            if (hwnd) {
                RealtimeLogger::getInstance().log("VideoSwitcher HWND obtained, starting WGC capture.");

                // Create a D3D11 device for the video pipeline
                ID3D11Device* d3dDevice = nullptr;
                ID3D11DeviceContext* d3dCtx = nullptr;
                D3D_FEATURE_LEVEL featureLevel;
                HRESULT hr = D3D11CreateDevice(
                    nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr,
                    D3D11_CREATE_DEVICE_BGRA_SUPPORT,
                    nullptr, 0, D3D11_SDK_VERSION,
                    &d3dDevice, &featureLevel, &d3dCtx);
                if (SUCCEEDED(hr) && d3dDevice) {
                    VideoCaptureManager captureMgr;
                    captureMgr.initialize(d3dDevice);
                    captureMgr.addWindowSource(0, hwnd);
                    captureMgr.startAll();

                    // Start the video engine render loop
                    VideoEngineCore videoEngine;
                    videoEngine.setSyncManager(&captureMgr.getSyncManager());
                    videoEngine.start();

                    RealtimeLogger::getInstance().log("Video pipeline started: WGC capture + VideoEngineCore render loop.");

                    int result = app.exec();

                    // Cleanup
                    videoEngine.stop();
                    captureMgr.stopAll();
                    d3dCtx->Release();
                    d3dDevice->Release();

                    // Cleanup engines
                    for (auto* e : engines) delete e;

                    SystemWatchdog::getInstance().stop();
                    RealtimeLogger::getInstance().stop();
                    return result;
                }
            }
        }
    }

    RealtimeLogger::getInstance().log("VideoSwitcher window not found — running without WGC capture.");

    int result = app.exec();

    // Cleanup engines
    for (auto* e : engines) delete e;

    // Shutdown background watchdog and logger threads safely before exit
    SystemWatchdog::getInstance().stop();
    RealtimeLogger::getInstance().stop();

    return result;
}
