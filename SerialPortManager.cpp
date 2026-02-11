#include "SerialPortManager.h"

SerialPortManager::SerialPortManager(QObject *parent)
    : QObject(parent)
    , m_serialPort(new QSerialPort(this))
    , m_rxBytes(0)
    , m_txBytes(0)
{
    connect(m_serialPort, &QSerialPort::readyRead,
            this, &SerialPortManager::handleReadyRead);
    connect(m_serialPort, &QSerialPort::errorOccurred,
            this, &SerialPortManager::handleError);
    refreshPorts();
}

SerialPortManager::~SerialPortManager()
{
    if (m_serialPort->isOpen())
        m_serialPort->close();
}

QStringList SerialPortManager::availablePorts() const
{
    return m_availablePorts;
}

bool SerialPortManager::isConnected() const
{
    return m_serialPort->isOpen();
}

qint64 SerialPortManager::rxBytes() const { return m_rxBytes; }
qint64 SerialPortManager::txBytes() const { return m_txBytes; }

void SerialPortManager::refreshPorts()
{
    m_availablePorts.clear();
    const auto ports = QSerialPortInfo::availablePorts();
    for (const auto &port : ports)
        m_availablePorts.append(port.portName() + QStringLiteral(" - ") + port.description());
    emit availablePortsChanged();
}

bool SerialPortManager::connectToPort(const QString &portName, int baudRate,
                                      int dataBits, int stopBits, int parity)
{
    if (m_serialPort->isOpen())
        m_serialPort->close();

    QString name = portName.split(QStringLiteral(" - ")).first().trimmed();
    m_serialPort->setPortName(name);
    m_serialPort->setBaudRate(baudRate);

    switch (dataBits) {
    case 5: m_serialPort->setDataBits(QSerialPort::Data5); break;
    case 6: m_serialPort->setDataBits(QSerialPort::Data6); break;
    case 7: m_serialPort->setDataBits(QSerialPort::Data7); break;
    default: m_serialPort->setDataBits(QSerialPort::Data8); break;
    }

    switch (stopBits) {
    case 2:  m_serialPort->setStopBits(QSerialPort::TwoStop); break;
    default: m_serialPort->setStopBits(QSerialPort::OneStop); break;
    }

    switch (parity) {
    case 1:  m_serialPort->setParity(QSerialPort::EvenParity); break;
    case 2:  m_serialPort->setParity(QSerialPort::OddParity); break;
    default: m_serialPort->setParity(QSerialPort::NoParity); break;
    }

    if (m_serialPort->open(QIODevice::ReadWrite)) {
        m_rxBytes = 0;
        m_txBytes = 0;
        emit rxBytesChanged();
        emit txBytesChanged();
        emit connectedChanged();
        return true;
    }

    emit errorOccurred(m_serialPort->errorString());
    return false;
}

void SerialPortManager::disconnectPort()
{
    if (m_serialPort->isOpen()) {
        m_serialPort->close();
        emit connectedChanged();
    }
}

bool SerialPortManager::sendData(const QString &data, bool hexMode)
{
    if (!m_serialPort->isOpen())
        return false;

    QByteArray bytes;
    if (hexMode) {
        QString cleaned = data.simplified().remove(QLatin1Char(' '));
        bytes = QByteArray::fromHex(cleaned.toLatin1());
    } else {
        bytes = data.toUtf8();
    }

    qint64 written = m_serialPort->write(bytes);
    if (written > 0) {
        m_txBytes += written;
        emit txBytesChanged();
        return true;
    }
    return false;
}

void SerialPortManager::handleReadyRead()
{
    QByteArray data = m_serialPort->readAll();
    if (data.isEmpty())
        return;

    m_rxBytes += data.size();
    emit rxBytesChanged();

    QString timestamp = QDateTime::currentDateTime().toString(QStringLiteral("HH:mm:ss.zzz"));

    // Build ASCII representation, replace non-printable chars with '.'
    QString asciiStr;
    asciiStr.reserve(data.size());
    for (int i = 0; i < data.size(); ++i) {
        char c = data.at(i);
        if (c >= 32 && c <= 126)
            asciiStr += QLatin1Char(c);
        else if (c == '\n' || c == '\r')
            asciiStr += QLatin1Char(c);
        else
            asciiStr += QLatin1Char('.');
    }

    QString hexStr = QString::fromLatin1(data.toHex(' ')).toUpper();

    emit dataReceived(timestamp, asciiStr, hexStr);
}

void SerialPortManager::handleError(QSerialPort::SerialPortError error)
{
    if (error == QSerialPort::NoError)
        return;

    QString msg = m_serialPort->errorString();
    emit errorOccurred(msg);

    if (error == QSerialPort::ResourceError) {
        m_serialPort->close();
        emit connectedChanged();
    }
}
