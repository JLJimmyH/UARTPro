#include "HeadlessRunner.h"
#include <QCoreApplication>
#include <QDateTime>
#include <QJsonDocument>
#include <QJsonObject>
#include <cstdio>

// stderr 一律輸出 UTF-8 JSON,避免 Windows locale 字串經 qPrintable 變亂碼
static void printStderrJson(const QJsonObject &obj)
{
    fprintf(stderr, "%s\n", QJsonDocument(obj).toJson(QJsonDocument::Compact).constData());
    fflush(stderr);
}

HeadlessRunner::HeadlessRunner(const HeadlessOptions &opts, QObject *parent)
    : QObject(parent)
    , m_opts(opts)
{
    if (!m_opts.expectPattern.isEmpty())
        m_expect = QRegularExpression(m_opts.expectPattern);
    if (!m_opts.expectFailPattern.isEmpty())
        m_expectFail = QRegularExpression(m_opts.expectFailPattern);

    m_timeoutTimer.setSingleShot(true);
    connect(&m_timeoutTimer, &QTimer::timeout, this, &HeadlessRunner::onTimeout);

    connect(&m_serial, &SerialPortManager::dataReceived, this, &HeadlessRunner::onLine);
    connect(&m_serial, &SerialPortManager::connectionLost, this, &HeadlessRunner::onConnectionLost);
    connect(&m_serial, &SerialPortManager::reconnected, this, &HeadlessRunner::onReconnected);
    connect(&m_serial, &SerialPortManager::errorOccurred, this, &HeadlessRunner::onError);
}

int HeadlessRunner::start()
{
    if (!m_opts.recordPath.isEmpty()) {
        if (!m_logger.startLogging(m_opts.recordPath, m_opts.format)) {
            printStderrJson({ { QStringLiteral("event"), QStringLiteral("error") },
                              { QStringLiteral("reason"), QStringLiteral("record open failed") },
                              { QStringLiteral("path"), m_opts.recordPath } });
            return ExitRecordFail;
        }
    }

    if (!m_serial.connectToPort(m_opts.port, m_opts.baud, 8, 1, 0)) {
        printStderrJson({ { QStringLiteral("event"), QStringLiteral("error") },
                          { QStringLiteral("reason"), QStringLiteral("port open failed") },
                          { QStringLiteral("port"), m_opts.port } });
        m_logger.stopLogging();
        return ExitPortFail;
    }

    if (m_opts.timeoutSec > 0)
        m_timeoutTimer.start(m_opts.timeoutSec * 1000);

    emitEvent(QStringLiteral("start"),
              m_opts.port + QStringLiteral(" @ ") + QString::number(m_opts.baud));
    return 0;
}

void HeadlessRunner::shutdown()
{
    finish(ExitOk, QStringLiteral("interrupted"));
}

void HeadlessRunner::onLine(const QString &timestamp, const QString &asciiData,
                            const QString &hexData)
{
    Q_UNUSED(timestamp)

    if (m_logger.isLogging()) {
        if (m_opts.format == QLatin1String("jsonl")) {
            m_logger.logStructured(QStringLiteral("rx"), asciiData, hexData);
        } else {
            const QString iso = QDateTime::currentDateTime().toString(Qt::ISODateWithMs);
            m_logger.logLine(QStringLiteral("[") + iso + QStringLiteral("] RX> ") + asciiData);
        }
    }

    if (m_opts.streamStdout)
        emitStdoutLine(QStringLiteral("rx"), asciiData, hexData);

    // 失敗 pattern 優先: 同一行同時命中時以失敗為準
    if (m_expectFail.isValid() && !m_opts.expectFailPattern.isEmpty()
        && m_expectFail.match(asciiData).hasMatch()) {
        finish(ExitExpectFail, QStringLiteral("expect-fail matched"), asciiData);
        return;
    }
    if (m_expect.isValid() && !m_opts.expectPattern.isEmpty()
        && m_expect.match(asciiData).hasMatch()) {
        finish(ExitOk, QStringLiteral("expect matched"), asciiData);
    }
}

void HeadlessRunner::onTimeout()
{
    finish(ExitTimeout, QStringLiteral("timeout"));
}

void HeadlessRunner::onConnectionLost()
{
    emitEvent(QStringLiteral("connection-lost"));
}

void HeadlessRunner::onReconnected()
{
    emitEvent(QStringLiteral("reconnected"));
}

void HeadlessRunner::onError(const QString &error)
{
    printStderrJson({ { QStringLiteral("event"), QStringLiteral("serial-error") },
                      { QStringLiteral("detail"), error } });
}

void HeadlessRunner::emitStdoutLine(const QString &type, const QString &ascii,
                                    const QString &hex)
{
    QJsonObject obj;
    obj[QStringLiteral("ts")] = QDateTime::currentDateTime().toString(Qt::ISODateWithMs);
    obj[QStringLiteral("type")] = type;
    obj[QStringLiteral("ascii")] = ascii;
    if (!hex.isEmpty())
        obj[QStringLiteral("hex")] = hex;
    printf("%s\n", QJsonDocument(obj).toJson(QJsonDocument::Compact).constData());
    fflush(stdout);
}

void HeadlessRunner::emitEvent(const QString &event, const QString &detail)
{
    QJsonObject obj;
    obj[QStringLiteral("ts")] = QDateTime::currentDateTime().toString(Qt::ISODateWithMs);
    obj[QStringLiteral("type")] = QStringLiteral("event");
    obj[QStringLiteral("event")] = event;
    if (!detail.isEmpty())
        obj[QStringLiteral("detail")] = detail;
    printf("%s\n", QJsonDocument(obj).toJson(QJsonDocument::Compact).constData());
    fflush(stdout);
}

void HeadlessRunner::finish(int code, const QString &reason, const QString &line)
{
    if (m_finished)
        return;
    m_finished = true;

    m_timeoutTimer.stop();
    m_serial.disconnectPort();
    m_logger.stopLogging();

    QJsonObject obj;
    obj[QStringLiteral("ts")] = QDateTime::currentDateTime().toString(Qt::ISODateWithMs);
    obj[QStringLiteral("type")] = QStringLiteral("exit");
    obj[QStringLiteral("code")] = code;
    obj[QStringLiteral("reason")] = reason;
    if (!line.isEmpty())
        obj[QStringLiteral("line")] = line;
    printf("%s\n", QJsonDocument(obj).toJson(QJsonDocument::Compact).constData());
    fflush(stdout);

    QCoreApplication::exit(code);
}
