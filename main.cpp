#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include "SerialPortManager.h"

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    app.setOrganizationName(QStringLiteral("UARTPro"));
    app.setApplicationName(QStringLiteral("UART PRO"));

    QQuickStyle::setStyle(QStringLiteral("Basic"));

    SerialPortManager serialManager;

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("serialManager"), &serialManager);

    const QUrl url(QStringLiteral("qrc:/UARTPro/main.qml"));
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreated, &app,
        [url](QObject *obj, const QUrl &objUrl) {
            if (!obj && url == objUrl)
                QCoreApplication::exit(-1);
        }, Qt::QueuedConnection);
    engine.load(url);

    return app.exec();
}
