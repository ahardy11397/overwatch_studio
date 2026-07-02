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
#include "core/control/WindowStateStore.h"
#include "core/control/ShowfileManager.h"
#include "core/video/VideoCaptureManager.h"
#include "core/video/VideoEngineCore.h"
#include <filesystem>
#include <vector>
#include <memory>
#include <QWindow>

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
    RealtimeLogger::getInstance().start("overwatch_studio_realtime.log");
    qInstallMessageHandler(qtMessageHandler);

    // Bootstrapping: Ensure default showfile exists
    auto appDir = std::filesystem::absolute(std::filesystem::path(argv[0]).parent_path());
    std::filesystem::path assetsDir = appDir / "assets/shows";
    if (!std::filesystem::exists(assetsDir)) {
        // Also try relative to repo root
        assetsDir = "assets/shows";
    }
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
        {"MasterLauncher", "src/ui/MasterLauncher.qml", "qrc:/qt/qml/overwatch_studio/src/ui/MasterLauncher.qml"},
        {"AudioConsole",   "src/ui/AudioConsole.qml",   "qrc:/qt/qml/overwatch_studio/src/ui/AudioConsole.qml"},
        {"VideoSwitcher",  "src/ui/VideoSwitcher.qml",  "qrc:/qt/qml/overwatch_studio/src/ui/VideoSwitcher.qml"},
        {"ShowBuilder",    "src/ui/ShowBuilder.qml",    "qrc:/qt/qml/overwatch_studio/src/ui/ShowBuilder.qml"},
    };

    std::vector<QQmlApplicationEngine*> engines;
    for (const auto& w : windows) {
        auto* eng = new QQmlApplicationEngine(&app);
        eng->rootContext()->setContextProperty("audioCore", &audioBridge);
        eng->rootContext()->setContextProperty("showBuilder", &showBuilderBridge);
        eng->addImportPath("qrc:/");
        eng->addImportPath("qrc:/qt/qml/");

        QString localPath = QString::fromLatin1(w.localPath);
        QString exePath = QCoreApplication::applicationDirPath() + "/" + localPath;
        QUrl url;
        if (QFile::exists(localPath)) {
            url = QUrl::fromLocalFile(localPath);
        } else if (QFile::exists(exePath)) {
            url = QUrl::fromLocalFile(exePath);
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

    RealtimeLogger::getInstance().log("All windows loaded. Starting optional video pipeline.");

    // Optional video pipeline: D3D11 + WGC capture + render loop
    // If any step fails, the app continues with mock video (camera images in VideoCanvasMock)
    std::unique_ptr<VideoCaptureManager> captureMgr;
    std::unique_ptr<VideoEngineCore> videoEngine;
    ID3D11Device* d3dDevice = nullptr;
    ID3D11DeviceContext* d3dCtx = nullptr;

    // Find the VideoSwitcher window to get its HWND for WGC capture
    for (auto* eng : engines) {
        auto roots = eng->rootObjects();
        if (roots.isEmpty()) continue;
        auto* qmlWin = qobject_cast<QWindow*>(roots.first());
        if (!qmlWin || !qmlWin->title().contains("Video Switcher")) continue;

        HWND hwnd = reinterpret_cast<HWND>(qmlWin->winId());
        if (!hwnd) break;

        D3D_FEATURE_LEVEL featureLevel;
        HRESULT hr = D3D11CreateDevice(
            nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr,
            D3D11_CREATE_DEVICE_BGRA_SUPPORT,
            nullptr, 0, D3D11_SDK_VERSION,
            &d3dDevice, &featureLevel, &d3dCtx);
        if (FAILED(hr) || !d3dDevice) break;

        captureMgr = std::make_unique<VideoCaptureManager>();
        captureMgr->initialize(d3dDevice);
        captureMgr->addWindowSource(0, hwnd);
        captureMgr->startAll();

        videoEngine = std::make_unique<VideoEngineCore>();
        videoEngine->setSyncManager(&captureMgr->getSyncManager());
        videoEngine->start();
        RealtimeLogger::getInstance().log("Video pipeline started: WGC capture + render loop.");
        break;
    }

    if (!videoEngine) {
        RealtimeLogger::getInstance().log("Video pipeline not started — using mock video.");
    }

    int result = app.exec();

    // Shutdown video pipeline
    if (videoEngine) videoEngine->stop();
    if (captureMgr) captureMgr->stopAll();
    if (d3dCtx) d3dCtx->Release();
    if (d3dDevice) d3dDevice->Release();

    // Cleanup engines
    for (auto* e : engines) delete e;

    // Shutdown background watchdog and logger threads safely before exit
    SystemWatchdog::getInstance().stop();
    RealtimeLogger::getInstance().stop();

    return result;
}
