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

public:
    explicit FileLogger(QObject *parent = nullptr);
    ~FileLogger();

    bool isLogging() const;
    qint64 logFileSize() const;
    QString logFilePath() const;

    Q_INVOKABLE bool startLogging(const QString &filePath);
    Q_INVOKABLE void stopLogging();
    Q_INVOKABLE void logEntry(const QString &timestamp, const QString &type,
                              const QString &message, const QString &hexData);
    Q_INVOKABLE QString generateDefaultPath() const;

    // CH-09: export helpers
    Q_INVOKABLE bool exportPlainText(const QString &filePath, const QVariantList &entries);
    Q_INVOKABLE bool exportCsv(const QString &filePath, const QVariantList &entries);

signals:
    void loggingChanged();
    void logFileSizeChanged();
    void logFilePathChanged();

private:
    void flushAndUpdateSize();

    QFile *m_file;
    QTextStream *m_stream;
    QTimer *m_flushTimer;
    qint64 m_logFileSize;
    QString m_logFilePath;
};

#endif // FILELOGGER_H
