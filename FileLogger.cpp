#include "FileLogger.h"
#include <QDir>
#include <QJsonDocument>
#include <QJsonObject>
#include <QUrl>
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

    // QML FileDialog 給 file:// URL;QUrl::toLocalFile 正確處理 drive path、UNC 與 percent-encoding
    QString localPath = filePath;
    const QUrl url(filePath);
    if (url.isLocalFile())
        localPath = url.toLocalFile();

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
                               const QString &hex, const QString &ts)
{
    if (!isLogging() || !m_stream)
        return;

    // 優先用擷取行時間(本地格式轉 ISODateWithMs);留空或解析失敗才用寫入當下時間。
    // ts 由 SerialPortManager 以固定格式 "yyyy-MM-dd HH:mm:ss.zzz"(23 字元)產生,
    // 快路徑只需把第 10 字元的空白換成 'T',免去每行 fromString 重建 parser
    QString isoTs;
    if (ts.size() == 23 && ts.at(10) == QLatin1Char(' ')) {
        isoTs = ts;
        isoTs[10] = QLatin1Char('T');
    } else if (!ts.isEmpty()) {
        QDateTime dt = QDateTime::fromString(ts, QStringLiteral("yyyy-MM-dd HH:mm:ss.zzz"));
        isoTs = dt.isValid() ? dt.toString(Qt::ISODateWithMs)
                             : QDateTime::currentDateTime().toString(Qt::ISODateWithMs);
    } else {
        isoTs = QDateTime::currentDateTime().toString(Qt::ISODateWithMs);
    }

    QJsonObject obj;
    obj[QStringLiteral("ts")] = isoTs;
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
    // QTextStream 底層寫入失敗(磁碟滿/檔案被刪/裝置拔除)後會靜默丟棄所有輸出,
    // 這裡是唯一的偵測點:失敗即停止記錄並通知 UI,避免使用者以為仍在錄
    if (m_stream->status() != QTextStream::Ok || m_file->error() != QFile::NoError) {
        const QString reason = m_file->errorString();
        stopLogging();
        emit writeError(reason);
        return;
    }
    qint64 newSize = m_file->size();
    if (newSize != m_logFileSize) {
        m_logFileSize = newSize;
        emit logFileSizeChanged();
    }
}

