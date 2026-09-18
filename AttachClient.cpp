#include "AttachClient.h"
#include <QCommandLineParser>
#include <QCoreApplication>
#include <QDir>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocalServer>
#include <QLocalSocket>
#include <cstdio>

#ifdef Q_OS_WIN
#include <windows.h>
#endif

// exit codes(與 headless 共用慣例,見 AGENT_INTEGRATION.md):
//   0=正常/expect 命中, 2=serial 操作失敗/連線中斷, 4=timeout,
//   5=expect-fail 命中, 6=參數無效, 7=無法定位目標實例
namespace {

constexpr int ExitOk = 0;
constexpr int ExitSerialFail = 2;
constexpr int ExitTimeout = 4;
constexpr int ExitExpectFail = 5;
constexpr int ExitBadArgs = 6;
constexpr int ExitNoInstance = 7;

void printLine(const QByteArray &utf8)
{
    fwrite(utf8.constData(), 1, utf8.size(), stdout);
    fputc('\n', stdout);
    fflush(stdout);
}

void printErrJson(const QString &error, const QJsonObject &extra = {})
{
    QJsonObject o = extra;
    o[QStringLiteral("error")] = error;
    fprintf(stderr, "%s\n", QJsonDocument(o).toJson(QJsonDocument::Compact).constData());
    fflush(stderr);
}

// Windows: pipe namespace 可直接列舉,pipe 名不含前綴
// macOS/Linux: QLocalServer 是 QDir::tempPath() 下的 unix socket 檔
QList<qint64> discoverPids()
{
    QList<qint64> pids;
#ifdef Q_OS_WIN
    WIN32_FIND_DATAW fd;
    HANDLE h = FindFirstFileW(L"\\\\.\\pipe\\*", &fd);
    if (h == INVALID_HANDLE_VALUE)
        return pids;
    do {
        const QString name = QString::fromWCharArray(fd.cFileName);
        if (name.startsWith(QLatin1String("UARTPro."))) {
            bool ok = false;
            const qint64 pid = name.mid(8).toLongLong(&ok);
            if (ok)
                pids.append(pid);
        }
    } while (FindNextFileW(h, &fd));
    FindClose(h);
#else
    // Windows 的 named pipe 隨 process 消失,unix socket 檔卻會留在磁碟上。
    // 光看檔名會把已結束的實例也算進來,所以逐一試連,連得上才算活著。
    const QDir tmp(QDir::tempPath());
    const auto entries = tmp.entryList(QStringList{QStringLiteral("UARTPro.*")},
                                       QDir::System | QDir::Files | QDir::NoDotAndDotDot);
    for (const QString &name : entries) {
        bool ok = false;
        const qint64 pid = name.mid(8).toLongLong(&ok);
        if (!ok)
            continue;
        QLocalSocket probe;
        probe.connectToServer(name);
        if (probe.waitForConnected(300)) {
            probe.disconnectFromServer();
            pids.append(pid);
        } else {
            // 前一個實例沒收乾淨的殘留 socket,順手清掉免得每次都試連逾時
            QLocalServer::removeServer(name);
        }
    }
#endif
    return pids;
}

// NDJSON 逐行讀取(單一 read 可能含多行或半行)
struct LineReader {
    QLocalSocket *sock;
    QByteArray buf;

    // 讀下一行;連線斷且 buffer 空 → false
    bool next(QByteArray &line, int timeoutMs = -1)
    {
        for (;;) {
            const int nl = buf.indexOf('\n');
            if (nl >= 0) {
                line = buf.left(nl).trimmed();
                buf.remove(0, nl + 1);
                if (line.isEmpty())
                    continue;
                return true;
            }
            if (sock->state() != QLocalSocket::ConnectedState) {
                buf.append(sock->readAll());
                if (buf.indexOf('\n') >= 0)
                    continue;
                return false;
            }
            // timeoutMs<0:每 60s 醒一次檢查連線狀態,實質等到斷線為止
            if (!sock->waitForReadyRead(timeoutMs < 0 ? 60000 : timeoutMs)) {
                if (timeoutMs >= 0)
                    return false;
                continue;
            }
            buf.append(sock->readAll());
        }
    }
};

bool connectPipe(QLocalSocket &sock, qint64 pid, int timeoutMs = 500)
{
    sock.connectToServer(QStringLiteral("UARTPro.") + QString::number(pid));
    return sock.waitForConnected(timeoutMs);
}

bool sendRequest(QLocalSocket &sock, const QJsonObject &req)
{
    sock.write(QJsonDocument(req).toJson(QJsonDocument::Compact) + '\n');
    return sock.waitForBytesWritten(1000);
}

// 一問一答:回 false 表示連不上或無回應
bool queryStatus(qint64 pid, QJsonObject &out)
{
    QLocalSocket sock;
    if (!connectPipe(sock, pid))
        return false;
    if (!sendRequest(sock, { { QStringLiteral("cmd"), QStringLiteral("status") } }))
        return false;
    LineReader reader{ &sock, {} };
    QByteArray line;
    if (!reader.next(line, 1000))
        return false;
    const QJsonDocument doc = QJsonDocument::fromJson(line);
    if (!doc.isObject())
        return false;
    out = doc.object();
    return true;
}

int verbList()
{
    QJsonArray arr;
    const QList<qint64> pids = discoverPids();
    for (const qint64 pid : pids) {
        QJsonObject st;
        if (queryStatus(pid, st)) {
            st.remove(QStringLiteral("ok"));
            arr.append(st);
        }
    }
    printLine(QJsonDocument(arr).toJson(QJsonDocument::Compact));
    return ExitOk;
}

// 定址:--pid > --port > 唯一實例;定不出來 → exit 7
int resolveTarget(const QCommandLineParser &parser, qint64 &outPid)
{
    if (parser.isSet(QStringLiteral("pid"))) {
        bool ok = false;
        const qint64 pid = parser.value(QStringLiteral("pid")).toLongLong(&ok);
        if (!ok || pid <= 0) {
            printErrJson(QStringLiteral("invalid --pid value"));
            return ExitBadArgs;
        }
        outPid = pid;
        return ExitOk;
    }

    const QList<qint64> pids = discoverPids();
    if (pids.isEmpty()) {
        printErrJson(QStringLiteral("no running UARTPro instance"));
        return ExitNoInstance;
    }

    if (parser.isSet(QStringLiteral("port"))) {
        const QString wanted = parser.value(QStringLiteral("port"));
        for (const qint64 pid : pids) {
            QJsonObject st;
            if (queryStatus(pid, st)
                && st.value(QStringLiteral("port")).toString()
                       .compare(wanted, Qt::CaseInsensitive) == 0) {
                outPid = pid;
                return ExitOk;
            }
        }
        printErrJson(QStringLiteral("no instance holds port ") + wanted);
        return ExitNoInstance;
    }

    if (pids.size() > 1) {
        printErrJson(QStringLiteral("multiple instances running — specify --pid or --port"),
                     { { QStringLiteral("count"), pids.size() } });
        return ExitNoInstance;
    }
    outPid = pids.first();
    return ExitOk;
}

// 串流動詞共用:印 entry 行,遇 envelope(done/result)依 verb 收尾
int runStreaming(LineReader &reader, bool isExpect)
{
    QByteArray line;
    while (reader.next(line)) {
        const QJsonDocument doc = QJsonDocument::fromJson(line);
        const QJsonObject o = doc.object();
        if (o.contains(QStringLiteral("done")))
            return ExitOk;   // tail 結束
        if (o.contains(QStringLiteral("result"))) {
            printLine(line);
            const QString result = o.value(QStringLiteral("result")).toString();
            if (result == QLatin1String("matched")) return ExitOk;
            if (result == QLatin1String("failed"))  return ExitExpectFail;
            return ExitTimeout;
        }
        printLine(line);
    }
    // 連線中斷:subscribe 屬正常結束(實例關閉),expect 未得結果屬異常
    if (isExpect) {
        printErrJson(QStringLiteral("connection closed before expect result"));
        return ExitSerialFail;
    }
    return ExitOk;
}

} // namespace

int runAttachClient(const QCommandLineParser &parser)
{
    QStringList pos = parser.positionalArguments();
    if (pos.isEmpty()) {
        printErrJson(QStringLiteral("usage: --attach <list|status|connect|disconnect|send|tail|subscribe|expect> [...]"));
        return ExitBadArgs;
    }
    const QString verb = pos.takeFirst();

    if (verb == QLatin1String("list"))
        return verbList();

    // 組 request(先驗參數再連線,fail fast)
    QJsonObject req;
    if (verb == QLatin1String("status") || verb == QLatin1String("disconnect")
        || verb == QLatin1String("subscribe")) {
        req[QStringLiteral("cmd")] = verb;
    } else if (verb == QLatin1String("connect")) {
        if (pos.isEmpty()) {
            printErrJson(QStringLiteral("usage: --attach connect <COMx> [baud]"));
            return ExitBadArgs;
        }
        int baud = 115200;
        if (pos.size() >= 2) {
            bool ok = false;
            baud = pos.at(1).toInt(&ok);
            if (!ok || baud <= 0) {
                printErrJson(QStringLiteral("invalid baud: ") + pos.at(1));
                return ExitBadArgs;
            }
        }
        req[QStringLiteral("cmd")] = QStringLiteral("connect");
        req[QStringLiteral("port")] = pos.first();
        req[QStringLiteral("baud")] = baud;
    } else if (verb == QLatin1String("send")) {
        if (pos.isEmpty()) {
            printErrJson(QStringLiteral("usage: --attach send <data> [--hex] [--eol none|cr|lf|crlf]"));
            return ExitBadArgs;
        }
        req[QStringLiteral("cmd")] = QStringLiteral("send");
        req[QStringLiteral("data")] = pos.first();
        req[QStringLiteral("hex")] = parser.isSet(QStringLiteral("hex"));
        req[QStringLiteral("eol")] = parser.isSet(QStringLiteral("eol"))
            ? parser.value(QStringLiteral("eol")) : QStringLiteral("crlf");
    } else if (verb == QLatin1String("tail")) {
        int count = 50;
        if (!pos.isEmpty()) {
            bool ok = false;
            count = pos.first().toInt(&ok);
            if (!ok || count <= 0) {
                printErrJson(QStringLiteral("invalid tail count: ") + pos.first());
                return ExitBadArgs;
            }
        }
        req[QStringLiteral("cmd")] = QStringLiteral("tail");
        req[QStringLiteral("count")] = count;
    } else if (verb == QLatin1String("expect")) {
        if (pos.isEmpty()) {
            printErrJson(QStringLiteral("usage: --attach expect <regex> [--expect-fail <regex>] [--timeout <sec>]"));
            return ExitBadArgs;
        }
        req[QStringLiteral("cmd")] = QStringLiteral("expect");
        req[QStringLiteral("pattern")] = pos.first();
        if (parser.isSet(QStringLiteral("expect-fail")))
            req[QStringLiteral("failPattern")] = parser.value(QStringLiteral("expect-fail"));
        if (parser.isSet(QStringLiteral("timeout"))) {
            bool ok = false;
            const int t = parser.value(QStringLiteral("timeout")).toInt(&ok);
            if (!ok || t < 0) {
                printErrJson(QStringLiteral("invalid --timeout value"));
                return ExitBadArgs;
            }
            req[QStringLiteral("timeoutSec")] = t;
        }
    } else {
        printErrJson(QStringLiteral("unknown attach verb: ") + verb);
        return ExitBadArgs;
    }

    qint64 pid = 0;
    const int rc = resolveTarget(parser, pid);
    if (rc != ExitOk)
        return rc;

    QLocalSocket sock;
    if (!connectPipe(sock, pid, 1000)) {
        printErrJson(QStringLiteral("cannot connect to instance pid ")
                     + QString::number(pid));
        return ExitNoInstance;
    }
    if (!sendRequest(sock, req)) {
        printErrJson(QStringLiteral("request write failed"));
        return ExitSerialFail;
    }

    LineReader reader{ &sock, {} };
    QByteArray line;
    if (!reader.next(line, 5000)) {
        printErrJson(QStringLiteral("no response from instance"));
        return ExitSerialFail;
    }
    const QJsonObject resp = QJsonDocument::fromJson(line).object();
    if (!resp.value(QStringLiteral("ok")).toBool(false)) {
        printErrJson(resp.value(QStringLiteral("error"))
                         .toString(QStringLiteral("request failed")));
        return ExitSerialFail;
    }

    if (verb == QLatin1String("status")) {
        printLine(line);
        return ExitOk;
    }
    if (verb == QLatin1String("tail") || verb == QLatin1String("subscribe")
        || verb == QLatin1String("expect"))
        return runStreaming(reader, verb == QLatin1String("expect"));

    // connect / disconnect / send:單一 ok 回應即完成
    printLine(line);
    return ExitOk;
}
