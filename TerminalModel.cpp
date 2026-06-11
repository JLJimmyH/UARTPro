#include "TerminalModel.h"
#include <QRegularExpression>

static const int FLUSH_INTERVAL_MS = 16;

TerminalModel::TerminalModel(QObject *parent)
    : QAbstractListModel(parent)
{
    m_flushTimer.setSingleShot(true);
    m_flushTimer.setInterval(FLUSH_INTERVAL_MS);
    connect(&m_flushTimer, &QTimer::timeout, this, &TerminalModel::flushPending);
}

int TerminalModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid())
        return 0;
    return m_visible.size();
}

QVariant TerminalModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_visible.size())
        return QVariant();

    const TerminalEntry &e = m_all.at(m_visible.at(index.row()));
    switch (role) {
    case TimestampRole:  return e.timestamp;
    case MsgTextRole:    return e.msgText;
    case HexDataRole:    return e.hexData;
    case TypeRole:       return e.type;
    case EntryIndexRole: return e.entryIndex;
    default:             return QVariant();
    }
}

QHash<int, QByteArray> TerminalModel::roleNames() const
{
    return {
        { TimestampRole,  QByteArrayLiteral("timestamp") },
        { MsgTextRole,    QByteArrayLiteral("msgText") },
        { HexDataRole,    QByteArrayLiteral("hexData") },
        { TypeRole,       QByteArrayLiteral("type") },
        { EntryIndexRole, QByteArrayLiteral("entryIndex") },
    };
}

void TerminalModel::setMaxLines(int lines)
{
    if (lines < 1 || m_maxLines == lines)
        return;
    m_maxLines = lines;
    emit maxLinesChanged();
    trimIfNeeded();
}

void TerminalModel::appendEntry(const QString &timestamp, const QString &msgText,
                                const QString &hexData, const QString &type)
{
    m_pending.append({ timestamp, msgText, hexData, type, 0 });
    if (!m_flushTimer.isActive())
        m_flushTimer.start();
}

void TerminalModel::appendRxLine(const QString &timestamp, const QString &asciiData,
                                 const QString &hexData)
{
    appendEntry(timestamp, asciiData, hexData, QStringLiteral("rx"));
}

void TerminalModel::flushPending()
{
    if (m_pending.isEmpty())
        return;

    QList<TerminalEntry> batch;
    batch.swap(m_pending);

    QVariantList appendedMaps;
    appendedMaps.reserve(batch.size());

    int visibleAdds = 0;
    for (TerminalEntry &e : batch) {
        e.entryIndex = m_nextIndex++;
        if (matchesFilter(e))
            ++visibleAdds;
        appendedMaps.append(entryToMap(e));
    }

    if (visibleAdds > 0) {
        const int first = m_visible.size();
        beginInsertRows(QModelIndex(), first, first + visibleAdds - 1);
        for (const TerminalEntry &e : batch) {
            m_all.append(e);
            if (matchesFilter(e))
                m_visible.append(m_all.size() - 1);
        }
        endInsertRows();
        emit countChanged();
    } else {
        for (const TerminalEntry &e : batch)
            m_all.append(e);
    }
    emit totalCountChanged();

    trimIfNeeded();

    emit entriesAppended(appendedMaps);
}

void TerminalModel::trimIfNeeded()
{
    if (m_all.size() <= m_maxLines)
        return;

    // 一次砍掉 10%(至少砍到不超過上限),把修剪頻率攤平
    const int removeCount = qMax(m_maxLines / 10, m_all.size() - m_maxLines);
    const int removedMaxEntryIndex = m_all.at(removeCount - 1).entryIndex;

    int visRemove = 0;
    while (visRemove < m_visible.size() && m_visible.at(visRemove) < removeCount)
        ++visRemove;

    if (visRemove > 0) {
        beginRemoveRows(QModelIndex(), 0, visRemove - 1);
        m_visible.remove(0, visRemove);
        endRemoveRows();
    }
    for (int &idx : m_visible)
        idx -= removeCount;

    m_all.remove(0, removeCount);

    if (visRemove > 0)
        emit countChanged();
    emit totalCountChanged();
    emit trimmed(removeCount, removedMaxEntryIndex);
}

bool TerminalModel::matchesFilter(const TerminalEntry &e) const
{
    // system / error 訊息永遠顯示
    if (e.type == QLatin1String("system") || e.type == QLatin1String("error"))
        return true;

    if (m_includes.isEmpty() && m_excludes.isEmpty())
        return true;

    const QString text = e.msgText.toLower();

    if (!m_includes.isEmpty()) {
        bool hit = false;
        for (const QString &inc : m_includes) {
            if (text.contains(inc)) {
                hit = true;
                break;
            }
        }
        if (!hit)
            return false;
    }

    for (const QString &exc : m_excludes) {
        if (text.contains(exc))
            return false;
    }
    return true;
}

void TerminalModel::setFilters(const QVariantList &filters)
{
    m_includes.clear();
    m_excludes.clear();
    for (const QVariant &v : filters) {
        const QVariantMap f = v.toMap();
        if (!f.value(QStringLiteral("enabled")).toBool())
            continue;
        const QString text = f.value(QStringLiteral("text")).toString().toLower();
        if (text.isEmpty())
            continue;
        if (f.value(QStringLiteral("filterType")).toString() == QLatin1String("include"))
            m_includes.append(text);
        else
            m_excludes.append(text);
    }

    beginResetModel();
    m_visible.clear();
    for (int i = 0; i < m_all.size(); ++i) {
        if (matchesFilter(m_all.at(i)))
            m_visible.append(i);
    }
    endResetModel();

    emit countChanged();
    emit filterActiveChanged();
}

QVariantList TerminalModel::search(const QString &query, bool isRegex, bool hexMode) const
{
    QVariantList matches;
    if (query.isEmpty())
        return matches;

    const QString pattern = isRegex ? query : QRegularExpression::escape(query);
    QRegularExpression re(pattern, QRegularExpression::CaseInsensitiveOption);
    if (!re.isValid())
        return matches;

    for (int row = 0; row < m_visible.size(); ++row) {
        const TerminalEntry &e = m_all.at(m_visible.at(row));
        const QString &text = (hexMode && !e.hexData.isEmpty()) ? e.hexData : e.msgText;
        if (re.match(text).hasMatch())
            matches.append(row);
    }
    return matches;
}

QVariantMap TerminalModel::get(int row) const
{
    if (row < 0 || row >= m_visible.size())
        return QVariantMap();
    return entryToMap(m_all.at(m_visible.at(row)));
}

void TerminalModel::clear()
{
    m_flushTimer.stop();
    m_pending.clear();
    beginResetModel();
    m_all.clear();
    m_visible.clear();
    m_nextIndex = 0;
    endResetModel();
    emit countChanged();
    emit totalCountChanged();
}

QVariantList TerminalModel::entriesForExport(bool filteredOnly) const
{
    QVariantList result;
    if (filteredOnly) {
        result.reserve(m_visible.size());
        for (int idx : m_visible)
            result.append(entryToMap(m_all.at(idx)));
    } else {
        result.reserve(m_all.size());
        for (const TerminalEntry &e : m_all)
            result.append(entryToMap(e));
    }
    return result;
}

QVariantList TerminalModel::allEntries() const
{
    return entriesForExport(false);
}

QVariantList TerminalModel::entryIndicesInRange(int loRow, int hiRow) const
{
    QVariantList result;
    const int lo = qBound(0, loRow, m_visible.size() - 1);
    const int hi = qBound(0, hiRow, m_visible.size() - 1);
    for (int row = lo; row <= hi; ++row)
        result.append(m_all.at(m_visible.at(row)).entryIndex);
    return result;
}

QVariantMap TerminalModel::entryToMap(const TerminalEntry &e)
{
    return {
        { QStringLiteral("timestamp"),  e.timestamp },
        { QStringLiteral("msgText"),    e.msgText },
        { QStringLiteral("hexData"),    e.hexData },
        { QStringLiteral("type"),       e.type },
        { QStringLiteral("entryIndex"), e.entryIndex },
    };
}
