#ifndef IPCSERVER_H
#define IPCSERVER_H

#include <QObject>
#include <QList>
#include <QRegularExpression>
#include <QVariantList>

class QLocalServer;
class QLocalSocket;
class QTimer;
class SerialPortManager;
class TerminalModel;

// 每個實例(GUI / headless)的本機命令介面:named pipe \\.\pipe\UARTPro.<pid>,
// NDJSON request/response。協議規格見 AGENT_INTEGRATION.md「Attach 模式」。
// 人與 agent 對等仲裁:不互鎖,agent 動作以 system 行 + agentAction signal(toast)可視化。
class IpcServer : public QObject
{
    Q_OBJECT
    Q_PROPERTY(int agentClients READ agentClients NOTIFY agentClientsChanged)

public:
    explicit IpcServer(SerialPortManager *serial, TerminalModel *model,
                       const QString &mode, QObject *parent = nullptr);

    bool start();   // listen 失敗(pipe 名衝突等)回 false,不影響主程式
    int agentClients() const { return m_clients.size(); }

signals:
    void agentClientsChanged();
    // GUI toast 用的一句話描述(connect/disconnect/send/subscribe/expect)
    void agentAction(const QString &text);
    // headless 記錄 agent TX 用(GUI 由 model 的 entriesAppended 路徑涵蓋)
    void agentSent(const QString &ts, const QString &ascii, const QString &hex);

private slots:
    void onNewConnection();
    void onEntriesAppended(const QVariantList &entries);

private:
    struct Client {
        QLocalSocket *sock = nullptr;
        enum Mode { Idle, Subscribe, Expect } mode = Idle;
        QRegularExpression expect;
        QRegularExpression expectFail;
        bool hasExpectFail = false;
        QTimer *timer = nullptr;   // expect 的 timeout
        QByteArray buf;
    };

    void handleRequest(Client *c, const QJsonObject &req);
    void cmdStatus(Client *c);
    void cmdConnect(Client *c, const QJsonObject &req);
    void cmdDisconnect(Client *c);
    void cmdSend(Client *c, const QJsonObject &req);
    void cmdTail(Client *c, const QJsonObject &req);
    void cmdSubscribe(Client *c);
    void cmdExpect(Client *c, const QJsonObject &req);

    void sendJson(QLocalSocket *sock, const QJsonObject &obj);
    void sendError(Client *c, const QString &error);
    void streamEntry(Client *c, const QVariantMap &entry);
    void finishExpect(Client *c, const QString &result, const QString &line);
    void appendSystemLine(const QString &msg);
    void dropClient(QLocalSocket *sock);
    static QString nowTs();

    SerialPortManager *m_serial;
    TerminalModel *m_model;
    QString m_mode;               // "gui" | "headless"
    QLocalServer *m_server = nullptr;
    QList<Client *> m_clients;
    int m_streamRefs = 0;         // 有 subscribe/expect client 時對 model 持 sink ref
};

#endif // IPCSERVER_H
