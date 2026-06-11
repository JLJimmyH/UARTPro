#ifndef FILELOGGER_H
#define FILELOGGER_H

#include <QObject>
#include <QFile>
#include <QTextStream>
#include <QTimer>
#include <QVariantList>
#include <QStandardPaths>
#include <QDateTime>

class FileLogger : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool logging READ isLogging NOTIFY loggingChanged)
    Q_PROPERTY(qint64 logFileSize READ logFileSize NOTIFY logFileSizeChanged)
    Q_PROPERTY(QString logFilePath READ logFilePath NOTIFY logFilePathChanged)
    Q_PROPERTY(QString format READ format NOTIFY formatChanged)

public:
    explicit FileLogger(QObject *parent = nullptr);
    ~FileLogger();

    bool isLogging() const;
    qint64 logFileSize() const;
    QString logFilePath() const;
    QString format() const;   // "text" | "jsonl"

    Q_INVOKABLE bool startLogging(const QString &filePath,
                                  const QString &format = QStringLiteral("text"));
    Q_INVOKABLE void stopLogging();
    Q_INVOKABLE void logLine(const QString &line);
    Q_INVOKABLE void logLines(const QStringList &lines);   // 批次寫入,單次 QML->C++ 跨界
    Q_INVOKABLE void logEntry(const QString &timestamp, const QString &type,
                              const QString &message, const QString &hexData);
    // JSONL 一筆: {"ts":ISO8601含毫秒,"seq":N,"type":...,"ascii":...,"hex":...}
    // schema 固定且與 UI 顯示偏好解耦,供 agent/LLM 穩定解析
    Q_INVOKABLE void logStructured(const QString &type, const QString &ascii,
                                   const QString &hex);
    Q_INVOKABLE QString generateDefaultPath() const;

    // CH-09: export helpers
    Q_INVOKABLE bool exportPlainText(const QString &filePath, const QVariantList &entries);
    Q_INVOKABLE bool exportCsv(const QString &filePath, const QVariantList &entries);

signals:
    void loggingChanged();
    void logFileSizeChanged();
    void logFilePathChanged();
    void formatChanged();

private:
    void flushAndUpdateSize();
    void writeSessionEvent(const QString &event);

    QFile *m_file;
    QTextStream *m_stream;
    QTimer *m_flushTimer;
    qint64 m_logFileSize;
    QString m_logFilePath;
    QString m_format = QStringLiteral("text");
    qint64 m_seq = 0;
};

#endif // FILELOGGER_H
