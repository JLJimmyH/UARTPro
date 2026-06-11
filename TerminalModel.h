#ifndef TERMINALMODEL_H
#define TERMINALMODEL_H

#include <QAbstractListModel>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>
#include <QStringList>

// 終端機資料層:單一儲存(取代 QML 的 terminalEntries JS array + ListModel 雙份)。
// - model 的 row = 通過 filter 的可見列;totalCount = 全部 entry 數
// - 收行先進 m_pending,16ms 批次 flush:一次 beginInsertRows,QML 每批只 layout 一次
// - 修剪在 C++ 端去頭,並以 trimmed signal 通知 QML 同步 selection/search 狀態
struct TerminalEntry {
    QString timestamp;   // 顯示用 "HH:mm:ss.zzz"
    QString msgText;
    QString hexData;
    QString type;        // "rx" | "tx" | "system" | "error"
    int     entryIndex;  // 全域遞增,clear 後歸零
};

class TerminalModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY countChanged)
    Q_PROPERTY(int totalCount READ totalCount NOTIFY totalCountChanged)
    Q_PROPERTY(int maxLines READ maxLines WRITE setMaxLines NOTIFY maxLinesChanged)
    Q_PROPERTY(bool filterActive READ filterActive NOTIFY filterActiveChanged)

public:
    enum Roles {
        TimestampRole = Qt::UserRole + 1,
        MsgTextRole,
        HexDataRole,
        TypeRole,
        EntryIndexRole
    };

    explicit TerminalModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    int count() const { return m_visible.size(); }
    int totalCount() const { return m_all.size(); }
    int maxLines() const { return m_maxLines; }
    void setMaxLines(int lines);
    bool filterActive() const { return !m_includes.isEmpty() || !m_excludes.isEmpty(); }

    Q_INVOKABLE void appendEntry(const QString &timestamp, const QString &msgText,
                                 const QString &hexData, const QString &type);
    Q_INVOKABLE QVariantMap get(int row) const;
    Q_INVOKABLE void clear();
    Q_INVOKABLE void setFilters(const QVariantList &filters);
    Q_INVOKABLE QVariantList search(const QString &query, bool isRegex, bool hexMode) const;
    Q_INVOKABLE QVariantList entriesForExport(bool filteredOnly) const;
    Q_INVOKABLE QVariantList allEntries() const;
    Q_INVOKABLE QVariantList entryIndicesInRange(int loRow, int hiRow) const;

public slots:
    void appendRxLine(const QString &timestamp, const QString &asciiData, const QString &hexData);

signals:
    void countChanged();
    void totalCountChanged();
    void maxLinesChanged();
    void filterActiveChanged();
    // 每批 flush 的所有 entry(含被 filter 掉的) — QML 用來寫 log + autoscroll
    void entriesAppended(const QVariantList &entries);
    void trimmed(int removedCount, int removedMaxEntryIndex);

private slots:
    void flushPending();

private:
    bool matchesFilter(const TerminalEntry &e) const;
    void trimIfNeeded();
    static QVariantMap entryToMap(const TerminalEntry &e);

    QList<TerminalEntry> m_all;
    QList<int> m_visible;          // m_all 的索引,遞增
    QList<TerminalEntry> m_pending;
    QStringList m_includes;        // 已 lowercase 的啟用 include filter
    QStringList m_excludes;
    QTimer m_flushTimer;
    int m_maxLines = 50000;
    int m_nextIndex = 0;
};

#endif // TERMINALMODEL_H
