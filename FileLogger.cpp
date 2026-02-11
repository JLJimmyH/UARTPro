#include "FileLogger.h"
#include <QDir>
#include <QFileInfo>
#include <QVariantMap>

FileLogger::FileLogger(QObject *parent)
    : QObject(parent)
    , m_file(nullptr)
    , m_stream(nullptr)
    , m_flushTimer(new QTimer(this))
    , m_logFileSize(0)
{
    m_flushTimer->setInterval(2000);
    connect(m_flushTimer, &QTimer::timeout, this, &FileLogger::flushAndUpdateSize);
}

FileLogger::~FileLogger()
{
    stopLogging();
}

bool FileLogger::isLogging() const
{
    return m_file != nullptr && m_file->isOpen();
}

qint64 FileLogger::logFileSize() const
{
    return m_logFileSize;
}

QString FileLogger::logFilePath() const
{
    return m_logFilePath;
}

bool FileLogger::startLogging(const QString &filePath)
{
    if (isLogging())
        stopLogging();

    QString localPath = filePath;
    // Strip file:/// prefix (from QML FileDialog)
    if (localPath.startsWith(QStringLiteral("file:///")))
        localPath = localPath.mid(8);
    else if (localPath.startsWith(QStringLiteral("file://")))
        localPath = localPath.mid(7);

    m_file = new QFile(localPath, this);
    if (!m_file->open(QIODevice::Append | QIODevice::Text)) {
        delete m_file;
        m_file = nullptr;
        return false;
    }

    m_stream = new QTextStream(m_file);
    m_stream->setEncoding(QStringConverter::Utf8);

    m_logFilePath = localPath;
    m_logFileSize = m_file->size();

    // Write session header
    *m_stream << QStringLiteral("=== UART PRO Log Session — ")
              << QDateTime::currentDateTime().toString(QStringLiteral("yyyy-MM-dd HH:mm:ss"))
              << QStringLiteral(" ===\n");

    m_flushTimer->start();
    emit loggingChanged();
    emit logFilePathChanged();
    emit logFileSizeChanged();
    return true;
}

void FileLogger::stopLogging()
{
    if (!isLogging())
        return;

    m_flushTimer->stop();

    // Write session footer
    *m_stream << QStringLiteral("=== Session ended — ")
              << QDateTime::currentDateTime().toString(QStringLiteral("yyyy-MM-dd HH:mm:ss"))
              << QStringLiteral(" ===\n\n");

    m_stream->flush();
    delete m_stream;
    m_stream = nullptr;

    m_logFileSize = m_file->size();

    m_file->close();
    delete m_file;
    m_file = nullptr;

    emit loggingChanged();
    emit logFileSizeChanged();
}

void FileLogger::logEntry(const QString &timestamp, const QString &type,
                          const QString &message, const QString &hexData)
{
    if (!isLogging() || !m_stream)
        return;

    *m_stream << QStringLiteral("[") << timestamp << QStringLiteral("] ")
              << type.toUpper() << QStringLiteral("> ") << message;

    if (!hexData.isEmpty())
        *m_stream << QStringLiteral("  |HEX: ") << hexData;

    *m_stream << QStringLiteral("\n");
}

QString FileLogger::generateDefaultPath() const
{
    QString docsPath = QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation);
    QString fileName = QStringLiteral("UARTPRO_%1.log")
                           .arg(QDateTime::currentDateTime().toString(QStringLiteral("yyyyMMdd_HHmmss")));
    return QDir(docsPath).filePath(fileName);
}

void FileLogger::flushAndUpdateSize()
{
    if (!isLogging())
        return;

    m_stream->flush();
    qint64 newSize = m_file->size();
    if (newSize != m_logFileSize) {
        m_logFileSize = newSize;
        emit logFileSizeChanged();
    }
}

// ── CH-09: Export helpers ─────────────────────────────────────

bool FileLogger::exportPlainText(const QString &filePath, const QVariantList &entries)
{
    QString localPath = filePath;
    if (localPath.startsWith(QStringLiteral("file:///")))
        localPath = localPath.mid(8);
    else if (localPath.startsWith(QStringLiteral("file://")))
        localPath = localPath.mid(7);

    QFile file(localPath);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text))
        return false;

    QTextStream out(&file);
    out.setEncoding(QStringConverter::Utf8);

    for (const QVariant &v : entries) {
        QVariantMap e = v.toMap();
        out << QStringLiteral("[") << e.value(QStringLiteral("timestamp")).toString()
            << QStringLiteral("] ")
            << e.value(QStringLiteral("type")).toString().toUpper()
            << QStringLiteral("> ")
            << e.value(QStringLiteral("msgText")).toString();

        QString hex = e.value(QStringLiteral("hexData")).toString();
        if (!hex.isEmpty())
            out << QStringLiteral("  |HEX: ") << hex;

        out << QStringLiteral("\n");
    }

    file.close();
    return true;
}

static QString csvEscape(const QString &field)
{
    if (field.contains(QLatin1Char(',')) || field.contains(QLatin1Char('"'))
        || field.contains(QLatin1Char('\n'))) {
        QString escaped = field;
        escaped.replace(QLatin1Char('"'), QStringLiteral("\"\""));
        return QStringLiteral("\"") + escaped + QStringLiteral("\"");
    }
    return field;
}

bool FileLogger::exportCsv(const QString &filePath, const QVariantList &entries)
{
    QString localPath = filePath;
    if (localPath.startsWith(QStringLiteral("file:///")))
        localPath = localPath.mid(8);
    else if (localPath.startsWith(QStringLiteral("file://")))
        localPath = localPath.mid(7);

    QFile file(localPath);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text))
        return false;

    QTextStream out(&file);
    out.setEncoding(QStringConverter::Utf8);

    // CSV header
    out << QStringLiteral("Timestamp,Type,Message,HexData\n");

    for (const QVariant &v : entries) {
        QVariantMap e = v.toMap();
        out << csvEscape(e.value(QStringLiteral("timestamp")).toString()) << QLatin1Char(',')
            << csvEscape(e.value(QStringLiteral("type")).toString().toUpper()) << QLatin1Char(',')
            << csvEscape(e.value(QStringLiteral("msgText")).toString()) << QLatin1Char(',')
            << csvEscape(e.value(QStringLiteral("hexData")).toString()) << QLatin1Char('\n');
    }

    file.close();
    return true;
}
