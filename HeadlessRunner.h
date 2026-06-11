#ifndef HEADLESSRUNNER_H
#define HEADLESSRUNNER_H

#include <QObject>
#include <QRegularExpression>
#include <QTimer>
#include "SerialPortManager.h"
#include "FileLogger.h"

// --headless 模式: 不載 QML,純錄製/串流/pattern 等待。
// exit codes: 0=正常或 expect 命中, 2=port 開啟失敗, 3=record 開檔失敗,
//             4=timeout, 5=expect-fail 命中
struct HeadlessOptions {
    QString port;
    int baud = 115200;
    QString recordPath;
    QString format = QStringLiteral("text");   // "text" | "jsonl"
    bool streamStdout = false;                 // 每行 JSONL 即時印到 stdout
    QString expectPattern;
    QString expectFailPattern;
    int timeoutSec = 0;
};

class HeadlessRunner : public QObject
{
    Q_OBJECT
public:
    enum ExitCode {
        ExitOk = 0,
        ExitPortFail = 2,
        ExitRecordFail = 3,
        ExitTimeout = 4,
        ExitExpectFail = 5
    };

    explicit HeadlessRunner(const HeadlessOptions &opts, QObject *parent = nullptr);

    // 回傳 0 表示啟動成功(進事件迴圈), 非 0 為立即失敗的 exit code
    int start();

public slots:
    void shutdown();   // Ctrl+C / SIGTERM

private slots:
    void onLine(const QString &timestamp, const QString &asciiData, const QString &hexData);
    void onTimeout();
    void onConnectionLost();
    void onReconnected();
    void onError(const QString &error);

private:
    void emitStdoutLine(const QString &type, const QString &ascii, const QString &hex);
    void emitEvent(const QString &event, const QString &detail = QString());
    void finish(int code, const QString &reason, const QString &line = QString());

    HeadlessOptions m_opts;
    SerialPortManager m_serial;
    FileLogger m_logger;
    QRegularExpression m_expect;
    QRegularExpression m_expectFail;
    QTimer m_timeoutTimer;
    bool m_finished = false;
};

#endif // HEADLESSRUNNER_H
