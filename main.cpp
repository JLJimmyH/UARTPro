#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QCommandLineParser>
#include "SerialPortManager.h"
#include "FileLogger.h"
#include "ConfigManager.h"
#include "version.h"

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

    return app.exec();
}
