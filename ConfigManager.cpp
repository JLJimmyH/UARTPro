#include "ConfigManager.h"
#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>

static const int SAVE_DEBOUNCE_MS = 500;
static const int CONFIG_VERSION = 2;

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

    auto readArray = [](const QJsonArray &arr, const QString &arrayType) -> QVariantList {
        QVariantList result;
        for (const QJsonValue &v : arr) {
            QJsonObject obj = v.toObject();
            QVariantMap item;
            item[QStringLiteral("text")] = obj.value(QStringLiteral("text")).toString();

            if (arrayType == QStringLiteral("keywords")) {
                item[QStringLiteral("color")] = obj.value(QStringLiteral("color")).toString();
                item[QStringLiteral("enabled")] = obj.contains(QStringLiteral("enabled"))
                    ? obj.value(QStringLiteral("enabled")).toBool() : true;
                item[QStringLiteral("mode")] = obj.contains(QStringLiteral("mode"))
                    ? obj.value(QStringLiteral("mode")).toString() : QStringLiteral("bg");
            } else if (arrayType == QStringLiteral("filters")) {
                item[QStringLiteral("filterType")] = obj.value(QStringLiteral("filterType")).toString();
                item[QStringLiteral("enabled")] = obj.contains(QStringLiteral("enabled"))
                    ? obj.value(QStringLiteral("enabled")).toBool() : true;
            }
            result.append(item);
        }
        return result;
    };

    int version = root.value(QStringLiteral("version")).toInt(1);

    if (root.contains(QStringLiteral("keywords")))
        m_keywords = readArray(root.value(QStringLiteral("keywords")).toArray(), QStringLiteral("keywords"));
    else
        m_keywords.clear();

    if (version < 2) {
        // v1 → v2 migration: merge whitelist/blacklist into filters
        m_filters.clear();
        if (root.contains(QStringLiteral("whitelist"))) {
            QJsonArray wlArr = root.value(QStringLiteral("whitelist")).toArray();
            for (const QJsonValue &v : wlArr) {
                QVariantMap item;
                item[QStringLiteral("text")] = v.toObject().value(QStringLiteral("text")).toString();
                item[QStringLiteral("filterType")] = QStringLiteral("include");
                item[QStringLiteral("enabled")] = true;
                m_filters.append(item);
            }
        }
        if (root.contains(QStringLiteral("blacklist"))) {
            QJsonArray blArr = root.value(QStringLiteral("blacklist")).toArray();
            for (const QJsonValue &v : blArr) {
                QVariantMap item;
                item[QStringLiteral("text")] = v.toObject().value(QStringLiteral("text")).toString();
                item[QStringLiteral("filterType")] = QStringLiteral("exclude");
                item[QStringLiteral("enabled")] = true;
                m_filters.append(item);
            }
        }
        // Ensure v1 keywords have enabled + mode defaults
        for (int i = 0; i < m_keywords.size(); ++i) {
            QVariantMap map = m_keywords[i].toMap();
            if (!map.contains(QStringLiteral("enabled")))
                map[QStringLiteral("enabled")] = true;
            if (!map.contains(QStringLiteral("mode")))
                map[QStringLiteral("mode")] = QStringLiteral("bg");
            m_keywords[i] = map;
        }
    } else {
        if (root.contains(QStringLiteral("filters")))
            m_filters = readArray(root.value(QStringLiteral("filters")).toArray(), QStringLiteral("filters"));
        else
            m_filters.clear();
    }

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

    auto writeArray = [](const QVariantList &list, const QString &arrayType) -> QJsonArray {
        QJsonArray arr;
        for (const QVariant &v : list) {
            QVariantMap map = v.toMap();
            QJsonObject obj;
            obj[QStringLiteral("text")] = map.value(QStringLiteral("text")).toString();

            if (arrayType == QStringLiteral("keywords")) {
                obj[QStringLiteral("color")] = map.value(QStringLiteral("color")).toString();
                obj[QStringLiteral("enabled")] = map.value(QStringLiteral("enabled")).toBool();
                obj[QStringLiteral("mode")] = map.value(QStringLiteral("mode")).toString();
            } else if (arrayType == QStringLiteral("filters")) {
                obj[QStringLiteral("filterType")] = map.value(QStringLiteral("filterType")).toString();
                obj[QStringLiteral("enabled")] = map.value(QStringLiteral("enabled")).toBool();
            }
            arr.append(obj);
        }
        return arr;
    };

    root[QStringLiteral("keywords")] = writeArray(m_keywords, QStringLiteral("keywords"));
    root[QStringLiteral("filters")]  = writeArray(m_filters,  QStringLiteral("filters"));

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

QVariantList ConfigManager::filters() const { return m_filters; }
void ConfigManager::setFilters(const QVariantList &list)
{
    m_filters = list;
    scheduleSave();
}
