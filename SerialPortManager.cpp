#include "SerialPortManager.h"

SerialPortManager::SerialPortManager(QObject *parent)
    : QObject(parent)
    , m_serialPort(new QSerialPort(this))
    , m_rxBytes(0)
    , m_txBytes(0)
    , m_reconnectTimer(new QTimer(this))
    , m_reconnecting(false)
    , m_lastBaudRate(115200)
    , m_lastDataBits(8)
    , m_lastStopBits(1)
    , m_lastParity(0)
{
    connect(m_serialPort, &QSerialPort::readyRead,
            this, &SerialPortManager::handleReadyRead);
    connect(m_serialPort, &QSerialPort::errorOccurred,
            this, &SerialPortManager::handleError);

    m_reconnectTimer->setInterval(1500);
    connect(m_reconnectTimer, &QTimer::timeout,
            this, &SerialPortManager::tryReconnect);

    refreshPorts();
}

SerialPortManager::~SerialPortManager()
{
    m_reconnectTimer->stop();
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

bool SerialPortManager::isReconnecting() const
{
    return m_reconnecting;
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

void SerialPortManager::applyPortSettings()
{
    m_serialPort->setPortName(m_lastPortName);
    m_serialPort->setBaudRate(m_lastBaudRate);

    switch (m_lastDataBits) {
    case 5: m_serialPort->setDataBits(QSerialPort::Data5); break;
    case 6: m_serialPort->setDataBits(QSerialPort::Data6); break;
    case 7: m_serialPort->setDataBits(QSerialPort::Data7); break;
    default: m_serialPort->setDataBits(QSerialPort::Data8); break;
    }

    switch (m_lastStopBits) {
    case 2:  m_serialPort->setStopBits(QSerialPort::TwoStop); break;
    default: m_serialPort->setStopBits(QSerialPort::OneStop); break;
    }

    switch (m_lastParity) {
    case 1:  m_serialPort->setParity(QSerialPort::EvenParity); break;
    case 2:  m_serialPort->setParity(QSerialPort::OddParity); break;
    default: m_serialPort->setParity(QSerialPort::NoParity); break;
    }
}

bool SerialPortManager::connectToPort(const QString &portName, int baudRate,
                                      int dataBits, int stopBits, int parity)
{
    // Stop any ongoing reconnect attempts
    if (m_reconnecting) {
        m_reconnectTimer->stop();
        m_reconnecting = false;
        emit reconnectingChanged();
    }

    if (m_serialPort->isOpen())
        m_serialPort->close();

    // Save connection parameters for auto-reconnect
    m_lastPortName = portName.split(QStringLiteral(" - ")).first().trimmed();
    m_lastBaudRate = baudRate;
    m_lastDataBits = dataBits;
    m_lastStopBits = stopBits;
    m_lastParity = parity;

    applyPortSettings();

    if (m_serialPort->open(QIODevice::ReadWrite)) {
        m_rxBuffer.clear();
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
    // Manual disconnect: stop auto-reconnect
    if (m_reconnecting) {
        m_reconnectTimer->stop();
        m_reconnecting = false;
        emit reconnectingChanged();
    }

    if (m_serialPort->isOpen()) {
        // Flush any remaining buffered data before closing
        if (!m_rxBuffer.isEmpty()) {
            emitLine(m_rxBuffer);
            m_rxBuffer.clear();
        }
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

void SerialPortManager::tryReconnect()
{
    // Check if port is available in system
    bool portExists = false;
    const auto ports = QSerialPortInfo::availablePorts();
    for (const auto &port : ports) {
        if (port.portName() == m_lastPortName) {
            portExists = true;
            break;
        }
    }

    if (!portExists)
        return;   // device not back yet, wait for next tick

    applyPortSettings();

    if (m_serialPort->open(QIODevice::ReadWrite)) {
        m_reconnectTimer->stop();
        m_reconnecting = false;
        emit reconnectingChanged();
        emit connectedChanged();
        emit reconnected();
    }
    // else: port appeared but open failed, keep trying
}

void SerialPortManager::handleReadyRead()
{
    QByteArray data = m_serialPort->readAll();
    if (data.isEmpty())
        return;

    m_rxBytes += data.size();
    emit rxBytesChanged();

    m_rxBuffer.append(data);

    // Split buffer by line endings (\r\n, \n, or \r)
    while (!m_rxBuffer.isEmpty()) {
        int idxLF = m_rxBuffer.indexOf('\n');
        int idxCR = m_rxBuffer.indexOf('\r');

        int splitPos = -1;
        int skipLen = 0;

        if (idxCR >= 0 && idxCR + 1 < m_rxBuffer.size() && m_rxBuffer.at(idxCR + 1) == '\n') {
            // \r\n
            splitPos = idxCR;
            skipLen = 2;
        } else if (idxLF >= 0 && (idxCR < 0 || idxLF < idxCR)) {
            // \n comes first
            splitPos = idxLF;
            skipLen = 1;
        } else if (idxCR >= 0) {
            // Lone \r — but if it's the last byte, it might be followed by \n in next chunk
            if (idxCR == m_rxBuffer.size() - 1) {
                // Wait for more data to determine if \r\n
                break;
            }
            splitPos = idxCR;
            skipLen = 1;
        } else {
            // No line ending found — keep in buffer
            break;
        }

        QByteArray lineData = m_rxBuffer.left(splitPos);
        m_rxBuffer.remove(0, splitPos + skipLen);

        emitLine(lineData);
    }
}

void SerialPortManager::emitLine(const QByteArray &lineData)
{
    if (lineData.isEmpty())
        return;

    QString timestamp = QDateTime::currentDateTime().toString(QStringLiteral("HH:mm:ss.zzz"));

    // Build ASCII representation, replace non-printable chars with '.'
    QString asciiStr;
    asciiStr.reserve(lineData.size());
    for (int i = 0; i < lineData.size(); ++i) {
        char c = lineData.at(i);
        if (c >= 32 && c <= 126)
            asciiStr += QLatin1Char(c);
        else
            asciiStr += QLatin1Char('.');
    }

    QString hexStr = QString::fromLatin1(lineData.toHex(' ')).toUpper();

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

        // Start auto-reconnect if we had a valid connection before
        if (!m_lastPortName.isEmpty() && !m_reconnecting) {
            m_reconnecting = true;
            emit reconnectingChanged();
            emit connectionLost();
            m_reconnectTimer->start();
        }
    }
}
