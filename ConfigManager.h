#ifndef CONFIGMANAGER_H
#define CONFIGMANAGER_H

#include <QObject>
#include <QTimer>
#include <QVariantList>
#include <QString>

class ConfigManager : public QObject
{
    Q_OBJECT

    Q_PROPERTY(qreal uiScale READ uiScale WRITE setUiScale NOTIFY uiScaleChanged)
    Q_PROPERTY(int terminalFontSize READ terminalFontSize WRITE setTerminalFontSize NOTIFY terminalFontSizeChanged)
    Q_PROPERTY(int currentTheme READ currentTheme WRITE setCurrentTheme NOTIFY currentThemeChanged)
    Q_PROPERTY(bool showPrefix READ showPrefix WRITE setShowPrefix NOTIFY showPrefixChanged)
    Q_PROPERTY(QString configFilePath READ configFilePath NOTIFY configFilePathChanged)

public:
    explicit ConfigManager(QObject *parent = nullptr);
    ~ConfigManager() override;

    qreal uiScale() const;
    int terminalFontSize() const;
    int currentTheme() const;
    bool showPrefix() const;
    QString configFilePath() const;

    void setUiScale(qreal value);
    void setTerminalFontSize(int value);
    void setCurrentTheme(int value);
    void setShowPrefix(bool value);

    Q_INVOKABLE QVariantList keywords() const;
    Q_INVOKABLE void setKeywords(const QVariantList &list);

    Q_INVOKABLE QVariantList whitelist() const;
    Q_INVOKABLE void setWhitelist(const QVariantList &list);

    Q_INVOKABLE QVariantList blacklist() const;
    Q_INVOKABLE void setBlacklist(const QVariantList &list);

    Q_INVOKABLE void loadFromFile(const QString &filePath);
    Q_INVOKABLE void setConfigPath(const QString &filePath);
    Q_INVOKABLE QString defaultConfigPath() const;

signals:
    void uiScaleChanged();
    void terminalFontSizeChanged();
    void currentThemeChanged();
    void showPrefixChanged();
    void configFilePathChanged();
    void configLoaded();

private slots:
    void saveToFile();

private:
    void scheduleSave();
    void loadInternal(const QString &path);
    static QString toLocalPath(const QString &path);

    qreal m_uiScale = 1.0;
    int m_terminalFontSize = 12;
    int m_currentTheme = 4;
    bool m_showPrefix = true;
    QString m_configFilePath;

    QVariantList m_keywords;
    QVariantList m_whitelist;
    QVariantList m_blacklist;

    QTimer *m_saveTimer;
    bool m_loading = false;
};

#endif // CONFIGMANAGER_H
