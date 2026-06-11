#include <QGuiApplication>
#include <QCoreApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QCommandLineParser>
#include <QAbstractNativeEventFilter>
#include <QSerialPortInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <cstdio>
#include <memory>
#include "SerialPortManager.h"
#include "FileLogger.h"
#include "ConfigManager.h"
#include "TerminalModel.h"
#include "HeadlessRunner.h"
#include "version.h"

#ifdef Q_OS_WIN
#include <windows.h>

class WindowsFramelessEventFilter : public QAbstractNativeEventFilter
{
public:
    explicit WindowsFramelessEventFilter(HWND hwnd)
        : m_hwnd(hwnd) {}

    bool nativeEventFilter(const QByteArray &eventType, void *message, qintptr *result) override
    {
        if (!m_hwnd)
            return false;

        if (eventType != "windows_generic_MSG" && eventType != "windows_dispatcher_MSG")
            return false;

        MSG *msg = static_cast<MSG *>(message);
        if (!msg || msg->hwnd != m_hwnd)
            return false;

        if (msg->message == WM_NCCALCSIZE && msg->wParam == TRUE) {
            *result = 0;
            return true;
        }

        return false;
    }

private:
    HWND m_hwnd = nullptr;
};

static void enableSnapForFramelessWindow(HWND hwnd)
{
    if (!hwnd)
        return;

    LONG_PTR style = GetWindowLongPtrW(hwnd, GWL_STYLE);
    const LONG_PTR snapStyleBits = WS_THICKFRAME | WS_MAXIMIZEBOX | WS_MINIMIZEBOX | WS_SYSMENU;
    const LONG_PTR newStyle = (style | snapStyleBits) & ~static_cast<LONG_PTR>(WS_CAPTION);
    if (newStyle != style) {
        SetWindowLongPtrW(hwnd, GWL_STYLE, newStyle);
        SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
                     SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
    }
}

// GUI subsystem 的 exe 預設沒有 console:
// - stdout 已被導向(pipe/檔案)時 handle 有效,CRT 直接可用
// - 互動 console 下 attach 回父行程 console 才看得到輸出
static void initConsoleIO()
{
    HANDLE h = GetStdHandle(STD_OUTPUT_HANDLE);
    if (h == nullptr || h == INVALID_HANDLE_VALUE) {
        if (AttachConsole(ATTACH_PARENT_PROCESS)) {
            FILE *f = nullptr;
            freopen_s(&f, "CONOUT$", "w", stdout);
            freopen_s(&f, "CONOUT$", "w", stderr);
        }
    }
}

static HeadlessRunner *g_runner = nullptr;

static BOOL WINAPI consoleCtrlHandler(DWORD type)
{
    Q_UNUSED(type)
    // 從 console handler 執行緒以 queued 方式回到事件迴圈收尾
    if (g_runner)
        QMetaObject::invokeMethod(g_runner, "shutdown", Qt::QueuedConnection);
    else if (qApp)
        QMetaObject::invokeMethod(qApp, "quit", Qt::QueuedConnection);
    return TRUE;
}
#endif

static bool hasArg(int argc, char *argv[], const char *name)
{
    for (int i = 1; i < argc; ++i) {
        if (qstrcmp(argv[i], name) == 0)
            return true;
    }
    return false;
}

static void setupParser(QCommandLineParser &parser)
{
    parser.setApplicationDescription(QStringLiteral("UART PRO Serial Terminal"));
    parser.addHelpOption();
    parser.addOption({ QStringLiteral("config"),
                       QStringLiteral("Path to configuration JSON file."),
                       QStringLiteral("path") });
    parser.addOption({ QStringLiteral("port"),
                       QStringLiteral("Auto-connect to this serial port on startup (e.g. COM3)."),
                       QStringLiteral("portName") });
    parser.addOption({ QStringLiteral("baud"),
                       QStringLiteral("Baud rate to use for auto-connect (e.g. 115200)."),
                       QStringLiteral("baudRate") });
    parser.addOption({ QStringLiteral("record"),
                       QStringLiteral("Auto-start logging to this file path on startup."),
                       QStringLiteral("filePath") });
    parser.addOption({ QStringLiteral("format"),
                       QStringLiteral("Record format: text (default) or jsonl."),
                       QStringLiteral("text|jsonl") });
    parser.addOption({ QStringLiteral("list-ports"),
                       QStringLiteral("Print available serial ports as JSON and exit.") });
    parser.addOption({ QStringLiteral("headless"),
                       QStringLiteral("Run without UI (requires --port). For automation/agents.") });
    parser.addOption({ QStringLiteral("stdout"),
                       QStringLiteral("Headless: stream each received line as JSONL to stdout.") });
    parser.addOption({ QStringLiteral("expect"),
                       QStringLiteral("Headless: exit 0 when a received line matches this regex."),
                       QStringLiteral("regex") });
    parser.addOption({ QStringLiteral("expect-fail"),
                       QStringLiteral("Headless: exit 5 when a received line matches this regex."),
                       QStringLiteral("regex") });
    parser.addOption({ QStringLiteral("timeout"),
                       QStringLiteral("Headless: exit 4 after this many seconds."),
                       QStringLiteral("seconds") });
}

// exit codes (headless / list-ports):
//   0 = 正常 / expect 命中 / 手動中斷
//   2 = port 開啟失敗或缺 --port
//   3 = record 檔開啟失敗
//   4 = timeout
//   5 = expect-fail 命中
static int runCli(int argc, char *argv[], bool listPorts)
{
    QCoreApplication app(argc, argv);
    app.setOrganizationName(QStringLiteral("UARTPro"));
    app.setApplicationName(QStringLiteral(APP_NAME));
    app.setApplicationVersion(QStringLiteral(APP_VERSION_STR));

#ifdef Q_OS_WIN
    initConsoleIO();
#endif

    QCommandLineParser parser;
    setupParser(parser);
    parser.process(app);

    if (listPorts) {
        QJsonArray arr;
        const auto ports = QSerialPortInfo::availablePorts();
        for (const auto &p : ports) {
            QJsonObject o;
            o[QStringLiteral("port")] = p.portName();
            o[QStringLiteral("description")] = p.description();
            o[QStringLiteral("manufacturer")] = p.manufacturer();
            arr.append(o);
        }
        printf("%s\n", QJsonDocument(arr).toJson(QJsonDocument::Compact).constData());
        fflush(stdout);
        return 0;
    }

    HeadlessOptions opts;
    opts.port = parser.value(QStringLiteral("port"));
    if (opts.port.isEmpty()) {
        fprintf(stderr, "--headless requires --port <COMx>\n");
        return HeadlessRunner::ExitPortFail;
    }
    if (parser.isSet(QStringLiteral("baud")))
        opts.baud = parser.value(QStringLiteral("baud")).toInt();
    opts.recordPath = parser.value(QStringLiteral("record"));
    if (parser.isSet(QStringLiteral("format")))
        opts.format = parser.value(QStringLiteral("format"));
    opts.streamStdout = parser.isSet(QStringLiteral("stdout"));
    opts.expectPattern = parser.value(QStringLiteral("expect"));
    opts.expectFailPattern = parser.value(QStringLiteral("expect-fail"));
    if (parser.isSet(QStringLiteral("timeout")))
        opts.timeoutSec = parser.value(QStringLiteral("timeout")).toInt();

    HeadlessRunner runner(opts);
#ifdef Q_OS_WIN
    g_runner = &runner;
    SetConsoleCtrlHandler(consoleCtrlHandler, TRUE);
#endif

    const int rc = runner.start();
    if (rc != 0)
        return rc;
    const int ret = app.exec();
#ifdef Q_OS_WIN
    g_runner = nullptr;
#endif
    return ret;
}

int main(int argc, char *argv[])
{
    // CLI 模式不建 QGuiApplication / QML engine
    if (hasArg(argc, argv, "--list-ports"))
        return runCli(argc, argv, true);
    if (hasArg(argc, argv, "--headless"))
        return runCli(argc, argv, false);

    QGuiApplication app(argc, argv);
    app.setOrganizationName(QStringLiteral("UARTPro"));
    app.setApplicationName(QStringLiteral(APP_NAME));
    app.setApplicationVersion(QStringLiteral(APP_VERSION_STR));

    QCommandLineParser parser;
    setupParser(parser);
    parser.process(app);

    QQuickStyle::setStyle(QStringLiteral("Basic"));

    SerialPortManager serialManager;
    FileLogger fileLogger;
    ConfigManager configManager;
    TerminalModel terminalModel;

    // RX 資料 C++ 直連 model(批次 flush),QML 不再逐行處理
    QObject::connect(&serialManager, &SerialPortManager::dataReceived,
                     &terminalModel, &TerminalModel::appendRxLine);

    QString configPath = parser.isSet(QStringLiteral("config"))
        ? parser.value(QStringLiteral("config"))
        : configManager.defaultConfigPath();
    configManager.loadFromFile(configPath);

    QString cmdLinePort   = parser.value(QStringLiteral("port"));
    int     cmdLineBaud   = parser.isSet(QStringLiteral("baud"))
                                ? parser.value(QStringLiteral("baud")).toInt() : 0;
    QString cmdLineRecord = parser.value(QStringLiteral("record"));
    QString cmdLineFormat = parser.isSet(QStringLiteral("format"))
                                ? parser.value(QStringLiteral("format")) : QStringLiteral("text");

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("serialManager"), &serialManager);
    engine.rootContext()->setContextProperty(QStringLiteral("fileLogger"), &fileLogger);
    engine.rootContext()->setContextProperty(QStringLiteral("configManager"), &configManager);
    engine.rootContext()->setContextProperty(QStringLiteral("terminalModel"), &terminalModel);
    engine.rootContext()->setContextProperty(QStringLiteral("appVersion"), QStringLiteral(APP_VERSION_STR));
    engine.rootContext()->setContextProperty(QStringLiteral("appName"), QStringLiteral(APP_NAME));
    engine.rootContext()->setContextProperty(QStringLiteral("cmdLinePort"),   cmdLinePort);
    engine.rootContext()->setContextProperty(QStringLiteral("cmdLineBaud"),   cmdLineBaud);
    engine.rootContext()->setContextProperty(QStringLiteral("cmdLineRecord"), cmdLineRecord);
    engine.rootContext()->setContextProperty(QStringLiteral("cmdLineFormat"), cmdLineFormat);

    const QUrl url(QStringLiteral("qrc:/qt/qml/UARTPro/main.qml"));
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreated, &app,
        [url](QObject *obj, const QUrl &objUrl) {
            if (!obj && url == objUrl)
                QCoreApplication::exit(-1);
        }, Qt::QueuedConnection);
    engine.load(url);

#ifdef Q_OS_WIN
    std::unique_ptr<WindowsFramelessEventFilter> framelessEventFilter;
    if (!engine.rootObjects().isEmpty()) {
        auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
        if (window) {
            HWND hwnd = reinterpret_cast<HWND>(window->winId());
            enableSnapForFramelessWindow(hwnd);
            framelessEventFilter = std::make_unique<WindowsFramelessEventFilter>(hwnd);
            app.installNativeEventFilter(framelessEventFilter.get());
        }
    }
#endif

    return app.exec();
}
