#include "ConfigManager.h"
#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>

static const int SAVE_DEBOUNCE_MS = 500;
static const int CONFIG_VERSION = 1;

ConfigManager::ConfigManager(QObject *parent)
    : QObject(parent)
    , m_saveTimer(new QTimer(this))
{
    m_saveTimer->setSingleShot(true);
    m_saveTimer->setInterval(SAVE_DEBOUNCE_MS);
    connect(m_saveTimer, &QTimer::timeout, this, &ConfigManager::saveToFile);
}

ConfigManager::~ConfigManager()
{
    if (m_saveTimer->isActive()) {
        m_saveTimer->stop();
        saveToFile();
    }
}

// ── Helpers ─────────────────────────────────────────

QString ConfigManager::toLocalPath(const QString &path)
{
    QString p = path;
    if (p.startsWith(QStringLiteral("file:///")))
        p = p.mid(8);
    else if (p.startsWith(QStringLiteral("file://")))
        p = p.mid(7);
    return p;
}

QString ConfigManager::defaultConfigPath() const
{
    return QDir(QCoreApplication::applicationDirPath())
        .filePath(QStringLiteral("uartpro_config.json"));
}

// ── File operations ─────────────────────────────────

void ConfigManager::setConfigPath(const QString &filePath)
{
    m_configFilePath = toLocalPath(filePath);
    emit configFilePathChanged();
}

void ConfigManager::loadFromFile(const QString &filePath)
{
    loadInternal(toLocalPath(filePath));
}

void ConfigManager::loadInternal(const QString &path)
{
    QFile file(path);

    if (!file.exists()) {
        m_configFilePath = path;
        emit configFilePathChanged();
        saveToFile();
        emit configLoaded();
        return;
    }

    if (!file.open(QIODevice::ReadOnly)) {
        m_configFilePath = path;
        emit configFilePathChanged();
        emit configLoaded();
        return;
    }

    QJsonParseError parseError;
    QJsonDocument doc = QJsonDocument::fromJson(file.readAll(), &parseError);
    file.close();

    if (parseError.error != QJsonParseError::NoError || !doc.isObject()) {
        m_configFilePath = path;
        emit configFilePathChanged();
        emit configLoaded();
        return;
    }

    m_loading = true;

    QJsonObject root = doc.object();

    if (root.contains(QStringLiteral("uiScale")))
        setUiScale(root.value(QStringLiteral("uiScale")).toDouble(1.0));
    if (root.contains(QStringLiteral("terminalFontSize")))
        setTerminalFontSize(root.value(QStringLiteral("terminalFontSize")).toInt(12));
    if (root.contains(QStringLiteral("currentTheme")))
        setCurrentTheme(root.value(QStringLiteral("currentTheme")).toInt(4));
    if (root.contains(QStringLiteral("showPrefix")))
        setShowPrefix(root.value(QStringLiteral("showPrefix")).toBool(true));

    auto readArray = [](const QJsonArray &arr, bool hasColor) -> QVariantList {
        QVariantList result;
        for (const QJsonValue &v : arr) {
            QJsonObject obj = v.toObject();
            QVariantMap item;
            item[QStringLiteral("text")] = obj.value(QStringLiteral("text")).toString();
            if (hasColor)
                item[QStringLiteral("color")] = obj.value(QStringLiteral("color")).toString();
            result.append(item);
        }
        return result;
    };

    if (root.contains(QStringLiteral("keywords")))
        m_keywords = readArray(root.value(QStringLiteral("keywords")).toArray(), true);
    else
        m_keywords.clear();

    if (root.contains(QStringLiteral("whitelist")))
        m_whitelist = readArray(root.value(QStringLiteral("whitelist")).toArray(), false);
    else
        m_whitelist.clear();

    if (root.contains(QStringLiteral("blacklist")))
        m_blacklist = readArray(root.value(QStringLiteral("blacklist")).toArray(), false);
    else
        m_blacklist.clear();

    m_configFilePath = path;
    emit configFilePathChanged();

    m_loading = false;
    emit configLoaded();
}

void ConfigManager::saveToFile()
{
    if (m_configFilePath.isEmpty())
        return;

    QJsonObject root;
    root[QStringLiteral("version")] = CONFIG_VERSION;
    root[QStringLiteral("uiScale")] = m_uiScale;
    root[QStringLiteral("terminalFontSize")] = m_terminalFontSize;
    root[QStringLiteral("currentTheme")] = m_currentTheme;
    root[QStringLiteral("showPrefix")] = m_showPrefix;

    auto writeArray = [](const QVariantList &list, bool hasColor) -> QJsonArray {
        QJsonArray arr;
        for (const QVariant &v : list) {
            QVariantMap map = v.toMap();
            QJsonObject obj;
            obj[QStringLiteral("text")] = map.value(QStringLiteral("text")).toString();
            if (hasColor)
                obj[QStringLiteral("color")] = map.value(QStringLiteral("color")).toString();
            arr.append(obj);
        }
        return arr;
    };

    root[QStringLiteral("keywords")] = writeArray(m_keywords, true);
    root[QStringLiteral("whitelist")] = writeArray(m_whitelist, false);
    root[QStringLiteral("blacklist")] = writeArray(m_blacklist, false);

    QJsonDocument doc(root);
    QFile file(m_configFilePath);
    if (file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        file.write(doc.toJson(QJsonDocument::Indented));
        file.close();
    }
}

void ConfigManager::scheduleSave()
{
    if (!m_loading)
        m_saveTimer->start();
}

// ── Getters ─────────────────────────────────────────

qreal ConfigManager::uiScale() const { return m_uiScale; }
int ConfigManager::terminalFontSize() const { return m_terminalFontSize; }
int ConfigManager::currentTheme() const { return m_currentTheme; }
bool ConfigManager::showPrefix() const { return m_showPrefix; }
QString ConfigManager::configFilePath() const { return m_configFilePath; }

// ── Setters ─────────────────────────────────────────

void ConfigManager::setUiScale(qreal value)
{
    value = qBound(0.6, value, 2.0);
    if (qFuzzyCompare(m_uiScale, value)) return;
    m_uiScale = value;
    emit uiScaleChanged();
    scheduleSave();
}

void ConfigManager::setTerminalFontSize(int value)
{
    value = qBound(8, value, 24);
    if (m_terminalFontSize == value) return;
    m_terminalFontSize = value;
    emit terminalFontSizeChanged();
    scheduleSave();
}

void ConfigManager::setCurrentTheme(int value)
{
    value = qBound(0, value, 7);
    if (m_currentTheme == value) return;
    m_currentTheme = value;
    emit currentThemeChanged();
    scheduleSave();
}

void ConfigManager::setShowPrefix(bool value)
{
    if (m_showPrefix == value) return;
    m_showPrefix = value;
    emit showPrefixChanged();
    scheduleSave();
}

// ── Array operations ────────────────────────────────

QVariantList ConfigManager::keywords() const { return m_keywords; }
void ConfigManager::setKeywords(const QVariantList &list)
{
    m_keywords = list;
    scheduleSave();
}

QVariantList ConfigManager::whitelist() const { return m_whitelist; }
void ConfigManager::setWhitelist(const QVariantList &list)
{
    m_whitelist = list;
    scheduleSave();
}

QVariantList ConfigManager::blacklist() const { return m_blacklist; }
void ConfigManager::setBlacklist(const QVariantList &list)
{
    m_blacklist = list;
    scheduleSave();
}
