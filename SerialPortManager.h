#ifndef SERIALPORTMANAGER_H
#define SERIALPORTMANAGER_H

#include <QObject>
#include <QSerialPort>
#include <QSerialPortInfo>
#include <QStringList>
#include <QDateTime>

class SerialPortManager : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QStringList availablePorts READ availablePorts NOTIFY availablePortsChanged)
    Q_PROPERTY(bool connected READ isConnected NOTIFY connectedChanged)
    Q_PROPERTY(qint64 rxBytes READ rxBytes NOTIFY rxBytesChanged)
    Q_PROPERTY(qint64 txBytes READ txBytes NOTIFY txBytesChanged)

public:
    explicit SerialPortManager(QObject *parent = nullptr);
    ~SerialPortManager();

    QStringList availablePorts() const;
    bool isConnected() const;
    qint64 rxBytes() const;
    qint64 txBytes() const;

    Q_INVOKABLE void refreshPorts();
    Q_INVOKABLE bool connectToPort(const QString &portName, int baudRate,
                                   int dataBits, int stopBits, int parity);
    Q_INVOKABLE void disconnectPort();
    Q_INVOKABLE bool sendData(const QString &data, bool hexMode);

signals:
    void availablePortsChanged();
    void connectedChanged();
    void rxBytesChanged();
    void txBytesChanged();
    void dataReceived(const QString &timestamp, const QString &asciiData, const QString &hexData);
    void errorOccurred(const QString &error);

private slots:
    void handleReadyRead();
    void handleError(QSerialPort::SerialPortError error);

private:
    void emitLine(const QByteArray &lineData);

    QSerialPort *m_serialPort;
    QStringList m_availablePorts;
    QByteArray m_rxBuffer;
    qint64 m_rxBytes;
    qint64 m_txBytes;
};

#endif // SERIALPORTMANAGER_H
