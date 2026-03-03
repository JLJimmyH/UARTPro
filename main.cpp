#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QCommandLineParser>
#include <QAbstractNativeEventFilter>
#include <QPointer>
#include <memory>
#include "SerialPortManager.h"
#include "FileLogger.h"
#include "ConfigManager.h"
#include "version.h"

#ifdef Q_OS_WIN
#include <windows.h>

class WindowsFramelessEventFilter : public QAbstractNativeEventFilter
{
public:
    explicit WindowsFramelessEventFilter(QQuickWindow *window)
        : m_window(window) {}

    bool nativeEventFilter(const QByteArray &eventType, void *message, qintptr *result) override
    {
        if (!m_window || !m_window->handle())
            return false;

        if (eventType != "windows_generic_MSG" && eventType != "windows_dispatcher_MSG")
            return false;

        MSG *msg = static_cast<MSG *>(message);
        if (!msg)
            return false;

        const HWND windowHwnd = reinterpret_cast<HWND>(m_window->winId());
        if (!windowHwnd)
            return false;

        if (msg->hwnd != windowHwnd)
            return false;

        if (msg->message == WM_NCCALCSIZE && msg->wParam == TRUE) {
            *result = 0;
            return true;
        }

        return false;
    }

private:
    QPointer<QQuickWindow> m_window;
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
#endif

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    app.setOrganizationName(QStringLiteral("UARTPro"));
    app.setApplicationName(QStringLiteral(APP_NAME));
    app.setApplicationVersion(QStringLiteral(APP_VERSION_STR));

    QCommandLineParser parser;
    parser.setApplicationDescription(QStringLiteral("UART PRO Serial Terminal"));
    parser.addHelpOption();
    QCommandLineOption configOption(
        QStringLiteral("config"),
        QStringLiteral("Path to configuration JSON file."),
        QStringLiteral("path"));
    parser.addOption(configOption);
    parser.process(app);

    QQuickStyle::setStyle(QStringLiteral("Basic"));

    SerialPortManager serialManager;
    FileLogger fileLogger;
    ConfigManager configManager;

    QString configPath = parser.isSet(configOption)
        ? parser.value(configOption)
        : configManager.defaultConfigPath();
    configManager.loadFromFile(configPath);

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("serialManager"), &serialManager);
    engine.rootContext()->setContextProperty(QStringLiteral("fileLogger"), &fileLogger);
    engine.rootContext()->setContextProperty(QStringLiteral("configManager"), &configManager);
    engine.rootContext()->setContextProperty(QStringLiteral("appVersion"), QStringLiteral(APP_VERSION_STR));
    engine.rootContext()->setContextProperty(QStringLiteral("appName"), QStringLiteral(APP_NAME));

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
            enableSnapForFramelessWindow(reinterpret_cast<HWND>(window->winId()));
            framelessEventFilter = std::make_unique<WindowsFramelessEventFilter>(window);
            app.installNativeEventFilter(framelessEventFilter.get());
        }
    }
#endif

    return app.exec();
}
