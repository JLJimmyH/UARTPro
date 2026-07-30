#ifndef ATTACHCLIENT_H
#define ATTACHCLIENT_H

class QCommandLineParser;

// --attach 模式:對執行中實例的 pipe 下命令。動詞與 exit code 見 AGENT_INTEGRATION.md。
// 需在 QCoreApplication 建立、parser.process 完成後呼叫。
int runAttachClient(const QCommandLineParser &parser);

#endif // ATTACHCLIENT_H
