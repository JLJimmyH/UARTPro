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
    Q_PROPERTY(bool hexDisplayMode READ hexDisplayMode WRITE setHexDisplayMode NOTIFY hexDisplayModeChanged)
    Q_PROPERTY(bool showTimestamp READ showTimestamp WRITE setShowTimestamp NOTIFY showTimestampChanged)
    Q_PROPERTY(bool showLineNumbers READ showLineNumbers WRITE setShowLineNumbers NOTIFY showLineNumbersChanged)
    Q_PROPERTY(bool colorNumbers READ colorNumbers WRITE setColorNumbers NOTIFY colorNumbersChanged)
    Q_PROPERTY(int maxBufferLines READ maxBufferLines WRITE setMaxBufferLines NOTIFY maxBufferLinesChanged)
    Q_PROPERTY(QString configFilePath READ configFilePath NOTIFY configFilePathChanged)

public:
    explicit ConfigManager(QObject *parent = nullptr);
    ~ConfigManager() override;

    qreal uiScale() const;
    int terminalFontSize() const;
    int currentTheme() const;
    bool showPrefix() const;
    bool hexDisplayMode() const;
    bool showTimestamp() const;
    bool showLineNumbers() const;
    bool colorNumbers() const;
    int maxBufferLines() const;
    QString configFilePath() const;

    void setUiScale(qreal value);
    void setTerminalFontSize(int value);
    void setCurrentTheme(int value);
    void setShowPrefix(bool value);
    void setHexDisplayMode(bool value);
    void setShowTimestamp(bool value);
    void setShowLineNumbers(bool value);
    void setColorNumbers(bool value);
    void setMaxBufferLines(int value);

    Q_INVOKABLE QVariantList keywords() const;
    Q_INVOKABLE void setKeywords(const QVariantList &list);

    Q_INVOKABLE QVariantList filters() const;
    Q_INVOKABLE void setFilters(const QVariantList &list);

    Q_INVOKABLE void loadFromFile(const QString &filePath);
    Q_INVOKABLE void setConfigPath(const QString &filePath);
    Q_INVOKABLE QString defaultConfigPath() const;

signals:
    void uiScaleChanged();
    void terminalFontSizeChanged();
    void currentThemeChanged();
    void showPrefixChanged();
    void hexDisplayModeChanged();
    void showTimestampChanged();
    void showLineNumbersChanged();
    void colorNumbersChanged();
    void maxBufferLinesChanged();
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
    bool m_hexDisplayMode = false;
    bool m_showTimestamp = true;
    bool m_showLineNumbers = false;
    bool m_colorNumbers = true;
    int m_maxBufferLines = 50000;
    QString m_configFilePath;

    QVariantList m_keywords;
    QVariantList m_filters;

    QTimer *m_saveTimer;
    bool m_loading = false;
};

#endif // CONFIGMANAGER_H
