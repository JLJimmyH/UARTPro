#include "IpcServer.h"
#include "SerialPortManager.h"
#include "TerminalModel.h"
#include <QCoreApplication>
#include <QDateTime>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocalServer>
#include <QLocalSocket>
#include <QTimer>
#include <QVariantMap>

IpcServer::IpcServer(SerialPortManager *serial, TerminalModel *model,
                     const QString &mode, QObject *parent)
    : QObject(parent)
    , m_serial(serial)
    , m_model(model)
    , m_mode(mode)
{
}

bool IpcServer::start()
{
    const QString name = QStringLiteral("UARTPro.")
        + QString::number(QCoreApplication::applicationPid());
    m_server = new QLocalServer(this);
    // 同 PID 殘留 pipe 幾乎不可能(Windows pipe 隨 process 消失),防禦性清一次
    QLocalServer::removeServer(name);
    if (!m_server->listen(name))
        return false;
    connect(m_server, &QLocalServer::newConnection, this, &IpcServer::onNewConnection);
    connect(m_model, &TerminalModel::entriesAppended, this, &IpcServer::onEntriesAppended);
    return true;
}

void IpcServer::onNewConnection()
{
    while (QLocalSocket *sock = m_server->nextPendingConnection()) {
        Client *c = new Client;
        c->sock = sock;
        m_clients.append(c);

        connect(sock, &QLocalSocket::readyRead, this, [this, c]() {
            c->buf.append(c->sock->readAll());
            int nl;
            while ((nl = c->buf.indexOf('\n')) >= 0) {
                const QByteArray line = c->buf.left(nl).trimmed();
                c->buf.remove(0, nl + 1);
                if (line.isEmpty())
                    continue;
                QJsonParseError err;
                const QJsonDocument doc = QJsonDocument::fromJson(line, &err);
                if (err.error != QJsonParseError::NoError || !doc.isObject()) {
                    sendError(c, QStringLiteral("invalid JSON request"));
                    continue;
                }
                handleRequest(c, doc.object());
            }
        });
        connect(sock, &QLocalSocket::disconnected, this, [this, sock]() {
            dropClient(sock);
        });

        emit agentClientsChanged();
    }
}

void IpcServer::handleRequest(Client *c, const QJsonObject &req)
{
    // 進入串流模式後連線專用於串流,不再受理命令
    if (c->mode != Client::Idle) {
        sendError(c, QStringLiteral("connection is in streaming mode"));
        return;
    }

    const QString cmd = req.value(QStringLiteral("cmd")).toString();
    if (cmd == QLatin1String("status"))          cmdStatus(c);
    else if (cmd == QLatin1String("connect"))    cmdConnect(c, req);
    else if (cmd == QLatin1String("disconnect")) cmdDisconnect(c);
    else if (cmd == QLatin1String("send"))       cmdSend(c, req);
    else if (cmd == QLatin1String("tail"))       cmdTail(c, req);
    else if (cmd == QLatin1String("subscribe"))  cmdSubscribe(c);
    else if (cmd == QLatin1String("expect"))     cmdExpect(c, req);
    else sendError(c, QStringLiteral("unknown cmd: ") + cmd);
}

void IpcServer::cmdStatus(Client *c)
{
    QJsonObject o;
    o[QStringLiteral("ok")] = true;
    o[QStringLiteral("pid")] = QCoreApplication::applicationPid();
    o[QStringLiteral("mode")] = m_mode;
    o[QStringLiteral("version")] = QCoreApplication::applicationVersion();
    o[QStringLiteral("port")] = m_serial->activePortName();
    o[QStringLiteral("baud")] = m_serial->activeBaudRate();
    o[QStringLiteral("connected")] = m_serial->isConnected();
    o[QStringLiteral("reconnecting")] = m_serial->isReconnecting();
    o[QStringLiteral("rxBytes")] = m_serial->rxBytes();
    o[QStringLiteral("txBytes")] = m_serial->txBytes();
    o[QStringLiteral("totalLines")] = m_model->totalCount();
    sendJson(c->sock, o);
}

void IpcServer::cmdConnect(Client *c, const QJsonObject &req)
{
    const QString port = req.value(QStringLiteral("port")).toString();
    const int baud = req.value(QStringLiteral("baud")).toInt(115200);
    if (port.isEmpty() || baud <= 0) {
        sendError(c, QStringLiteral("connect requires port and positive baud"));
        return;
    }
    // 與 GUI 相同,固定 8N1
    const bool ok = m_serial->connectToPort(port, baud, 8, 1, 0);
    const QString desc = port + QStringLiteral(" @ ") + QString::number(baud);
    if (ok) {
        appendSystemLine(QStringLiteral("[AGENT] connect ") + desc);
        emit agentAction(QStringLiteral("AGENT: connect ") + desc);
        sendJson(c->sock, { { QStringLiteral("ok"), true } });
    } else {
        appendSystemLine(QStringLiteral("[AGENT] connect ") + desc
                         + QStringLiteral(" — failed"));
        sendError(c, QStringLiteral("port open failed: ") + port);
    }
}

void IpcServer::cmdDisconnect(Client *c)
{
    m_serial->disconnectPort();
    appendSystemLine(QStringLiteral("[AGENT] disconnect"));
    emit agentAction(QStringLiteral("AGENT: disconnect"));
    sendJson(c->sock, { { QStringLiteral("ok"), true } });
}

void IpcServer::cmdSend(Client *c, const QJsonObject &req)
{
    const QString data = req.value(QStringLiteral("data")).toString();
    const bool hexMode = req.value(QStringLiteral("hex")).toBool(false);
    const QString eol = req.value(QStringLiteral("eol")).toString(QStringLiteral("crlf"));
    if (data.isEmpty()) {
        sendError(c, QStringLiteral("send requires data"));
        return;
    }

    QString toSend = data;
    if (!hexMode) {
        if (eol == QLatin1String("cr"))        toSend += QStringLiteral("\r");
        else if (eol == QLatin1String("lf"))   toSend += QStringLiteral("\n");
        else if (eol == QLatin1String("crlf")) toSend += QStringLiteral("\r\n");
        else if (eol != QLatin1String("none")) {
            sendError(c, QStringLiteral("invalid eol: ") + eol);
            return;
        }
    }

    if (!m_serial->sendData(toSend, hexMode)) {
        sendError(c, m_serial->isConnected()
                      ? QStringLiteral("send failed")
                      : QStringLiteral("not connected"));
        return;
    }

    // 與 GUI 的 sendCurrentData 一致:tx 行顯示原輸入(不含行尾)
    const QString ts = nowTs();
    m_model->appendEntry(ts, data, QString(), QStringLiteral("tx"));
    emit agentSent(ts, data, hexMode ? data : QString());
    emit agentAction(QStringLiteral("AGENT TX: ") + data.left(48));
    sendJson(c->sock, { { QStringLiteral("ok"), true } });
}

void IpcServer::cmdTail(Client *c, const QJsonObject &req)
{
    const int count = qBound(1, req.value(QStringLiteral("count")).toInt(50), 100000);
    const QVariantList entries = m_model->tailEntries(count);
    sendJson(c->sock, { { QStringLiteral("ok"), true },
                        { QStringLiteral("count"), entries.size() } });
    for (const QVariant &v : entries)
        streamEntry(c, v.toMap());
    sendJson(c->sock, { { QStringLiteral("done"), true } });
}

void IpcServer::cmdSubscribe(Client *c)
{
    c->mode = Client::Subscribe;
    if (++m_streamRefs == 1)
        m_model->addEntrySinkRef();
    appendSystemLine(QStringLiteral("[AGENT] subscribe"));
    emit agentAction(QStringLiteral("AGENT: subscribe"));
    sendJson(c->sock, { { QStringLiteral("ok"), true } });
}

void IpcServer::cmdExpect(Client *c, const QJsonObject &req)
{
    const QString pattern = req.value(QStringLiteral("pattern")).toString();
    if (pattern.isEmpty()) {
        sendError(c, QStringLiteral("expect requires pattern"));
        return;
    }
    c->expect = QRegularExpression(pattern);
    if (!c->expect.isValid()) {
        sendError(c, QStringLiteral("invalid pattern regex: ") + c->expect.errorString());
        return;
    }
    const QString failPattern = req.value(QStringLiteral("failPattern")).toString();
    c->hasExpectFail = !failPattern.isEmpty();
    if (c->hasExpectFail) {
        c->expectFail = QRegularExpression(failPattern);
        if (!c->expectFail.isValid()) {
            sendError(c, QStringLiteral("invalid failPattern regex: ")
                          + c->expectFail.errorString());
            return;
        }
    }

    c->mode = Client::Expect;
    if (++m_streamRefs == 1)
        m_model->addEntrySinkRef();

    const int timeoutSec = req.value(QStringLiteral("timeoutSec")).toInt(0);
    if (timeoutSec > 0) {
        c->timer = new QTimer(this);
        c->timer->setSingleShot(true);
        connect(c->timer, &QTimer::timeout, this, [this, c]() {
            finishExpect(c, QStringLiteral("timeout"), QString());
        });
        c->timer->start(timeoutSec * 1000);
    }

    appendSystemLine(QStringLiteral("[AGENT] expect ") + pattern);
    emit agentAction(QStringLiteral("AGENT: expect ") + pattern);
    sendJson(c->sock, { { QStringLiteral("ok"), true } });
}

void IpcServer::onEntriesAppended(const QVariantList &entries)
{
    if (m_streamRefs == 0)
        return;
    // finishExpect 會斷線 → dropClient 修改 m_clients,先複製再走訪
    const QList<Client *> clients = m_clients;
    for (Client *c : clients) {
        if (c->mode == Client::Subscribe) {
            for (const QVariant &v : entries)
                streamEntry(c, v.toMap());
        } else if (c->mode == Client::Expect) {
            for (const QVariant &v : entries) {
                const QVariantMap m = v.toMap();
                streamEntry(c, m);
                // 與 headless --expect 一致:只對 RX 行做 pattern 比對(不吃自己的 TX 回顯)
                if (m.value(QStringLiteral("type")).toString() != QLatin1String("rx"))
                    continue;
                const QString ascii = m.value(QStringLiteral("msgText")).toString();
                if (c->hasExpectFail && c->expectFail.match(ascii).hasMatch()) {
                    finishExpect(c, QStringLiteral("failed"), ascii);
                    break;
                }
                if (c->expect.match(ascii).hasMatch()) {
                    finishExpect(c, QStringLiteral("matched"), ascii);
                    break;
                }
            }
        }
    }
}

void IpcServer::sendJson(QLocalSocket *sock, const QJsonObject &obj)
{
    sock->write(QJsonDocument(obj).toJson(QJsonDocument::Compact) + '\n');
    sock->flush();
}

void IpcServer::sendError(Client *c, const QString &error)
{
    sendJson(c->sock, { { QStringLiteral("ok"), false },
                        { QStringLiteral("error"), error } });
}

void IpcServer::streamEntry(Client *c, const QVariantMap &entry)
{
    QJsonObject o;
    o[QStringLiteral("ts")] = entry.value(QStringLiteral("timestamp")).toString();
    o[QStringLiteral("idx")] = entry.value(QStringLiteral("entryIndex")).toInt();
    o[QStringLiteral("type")] = entry.value(QStringLiteral("type")).toString();
    o[QStringLiteral("ascii")] = entry.value(QStringLiteral("msgText")).toString();
    const QString hex = entry.value(QStringLiteral("hexData")).toString();
    if (!hex.isEmpty())
        o[QStringLiteral("hex")] = hex;
    sendJson(c->sock, o);
}

void IpcServer::finishExpect(Client *c, const QString &result, const QString &line)
{
    QJsonObject o;
    o[QStringLiteral("result")] = result;
    if (!line.isEmpty())
        o[QStringLiteral("line")] = line;
    sendJson(c->sock, o);
    c->sock->disconnectFromServer();   // 收尾交給 disconnected → dropClient
}

void IpcServer::appendSystemLine(const QString &msg)
{
    m_model->appendEntry(nowTs(), msg, QString(), QStringLiteral("system"));
}

void IpcServer::dropClient(QLocalSocket *sock)
{
    for (int i = 0; i < m_clients.size(); ++i) {
        Client *c = m_clients.at(i);
        if (c->sock != sock)
            continue;
        if (c->mode != Client::Idle && --m_streamRefs == 0)
            m_model->removeEntrySinkRef();
        if (c->timer)
            c->timer->deleteLater();
        m_clients.removeAt(i);
        delete c;
        sock->deleteLater();
        emit agentClientsChanged();
        return;
    }
}

QString IpcServer::nowTs()
{
    return QDateTime::currentDateTime().toString(QStringLiteral("yyyy-MM-dd HH:mm:ss.zzz"));
}
