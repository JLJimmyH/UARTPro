#include "FileLogger.h"
#include <QDir>
#include <QFileInfo>
#include <QVariantMap>
#include <QJsonDocument>
#include <QJsonObject>
#include "version.h"

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

QString FileLogger::format() const
{
    return m_format;
}

// 在 jsonl 模式下 session 標頭/結尾也是 JSONL 事件列,維持整檔可逐行解析
void FileLogger::writeSessionEvent(const QString &event)
{
    if (m_format == QLatin1String("jsonl")) {
        QJsonObject obj;
        obj[QStringLiteral("ts")] = QDateTime::currentDateTime().toString(Qt::ISODateWithMs);
        obj[QStringLiteral("type")] = QStringLiteral("session");
        obj[QStringLiteral("event")] = event;
        obj[QStringLiteral("app")] = QStringLiteral(APP_NAME);
        obj[QStringLiteral("version")] = QStringLiteral(APP_VERSION_STR);
        *m_stream << QString::fromUtf8(QJsonDocument(obj).toJson(QJsonDocument::Compact))
                  << QStringLiteral("\n");
    } else if (event == QLatin1String("start")) {
        *m_stream << QStringLiteral("=== UART PRO Log Session — ")
                  << QDateTime::currentDateTime().toString(QStringLiteral("yyyy-MM-dd HH:mm:ss"))
                  << QStringLiteral(" ===\n");
    } else {
        *m_stream << QStringLiteral("=== Session ended — ")
                  << QDateTime::currentDateTime().toString(QStringLiteral("yyyy-MM-dd HH:mm:ss"))
                  << QStringLiteral(" ===\n\n");
    }
}

bool FileLogger::startLogging(const QString &filePath, const QString &format)
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
    m_format = (format == QLatin1String("jsonl")) ? QStringLiteral("jsonl")
                                                  : QStringLiteral("text");
    m_seq = 0;
    emit formatChanged();

    writeSessionEvent(QStringLiteral("start"));

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

    writeSessionEvent(QStringLiteral("stop"));

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
    QString line = QStringLiteral("[") + timestamp + QStringLiteral("] ")
                 + type.toUpper() + QStringLiteral("> ") + message;
    if (!hexData.isEmpty())
        line += QStringLiteral("  |HEX: ") + hexData;
    logLine(line);
}

void FileLogger::logLine(const QString &line)
{
    if (!isLogging() || !m_stream)
        return;

    *m_stream << line << QStringLiteral("\n");
}

void FileLogger::logLines(const QStringList &lines)
{
    if (!isLogging() || !m_stream)
        return;

    for (const QString &line : lines)
        *m_stream << line << QStringLiteral("\n");
}

void FileLogger::logStructured(const QString &type, const QString &ascii,
                               const QString &hex)
{
    if (!isLogging() || !m_stream)
        return;

    QJsonObject obj;
    obj[QStringLiteral("ts")] = QDateTime::currentDateTime().toString(Qt::ISODateWithMs);
    obj[QStringLiteral("seq")] = m_seq++;
    obj[QStringLiteral("type")] = type;
    obj[QStringLiteral("ascii")] = ascii;
    if (!hex.isEmpty())
        obj[QStringLiteral("hex")] = hex;
    *m_stream << QString::fromUtf8(QJsonDocument(obj).toJson(QJsonDocument::Compact))
              << QStringLiteral("\n");
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
