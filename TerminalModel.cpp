#include "TerminalModel.h"
#include <QRegularExpression>
#include <QVarLengthArray>

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
    case HexDataRole:    return hexString(e);
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
    // QML 端傳入的是顯示用 hex 字串(通常為空),轉回原始 bytes 儲存
    m_pending.append({ timestamp, msgText, QByteArray::fromHex(hexData.toLatin1()), type, 0 });
    if (!m_flushTimer.isActive())
        m_flushTimer.start();
}

void TerminalModel::appendRxLine(const QString &timestamp, const QString &asciiData,
                                 const QByteArray &rawData)
{
    m_pending.append({ timestamp, asciiData, rawData, QStringLiteral("rx"), 0 });
    if (!m_flushTimer.isActive())
        m_flushTimer.start();
}

void TerminalModel::flushPending()
{
    if (m_pending.isEmpty())
        return;

    QList<TerminalEntry> batch;
    batch.swap(m_pending);

    // QVariantMap payload 只在有消費端(QML log sink 或 IPC 訂閱)時才建
    const bool wantMaps = m_logSinkActive || m_sinkRefs > 0;
    QVariantList appendedMaps;
    if (wantMaps)
        appendedMaps.reserve(batch.size());

    // matchesFilter 每次都 toLower 配置,結果存表避免第二輪重算
    QVarLengthArray<bool, 256> visible(batch.size());
    int visibleAdds = 0;
    for (int i = 0; i < batch.size(); ++i) {
        TerminalEntry &e = batch[i];
        e.entryIndex = m_nextIndex++;
        e.hlColor = computeHlColor(e);
        visible[i] = matchesFilter(e);
        if (visible[i])
            ++visibleAdds;
        if (wantMaps)
            appendedMaps.append(entryToMap(e));
    }

    if (visibleAdds > 0) {
        const int first = m_visible.size();
        beginInsertRows(QModelIndex(), first, first + visibleAdds - 1);
        for (int i = 0; i < batch.size(); ++i) {
            m_all.append(batch.at(i));
            if (visible[i])
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

    if (!appendedMaps.isEmpty())
        emit entriesAppended(appendedMaps);
    emit entriesFlushed();
}

void TerminalModel::setLogSinkActive(bool active)
{
    if (m_logSinkActive == active)
        return;
    m_logSinkActive = active;
    emit logSinkActiveChanged();
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

    // 回傳 entryIndex(非 row):row 會隨 append/trim/filter 位移,呼叫端存起來就會錯位
    for (int row = 0; row < m_visible.size(); ++row) {
        const TerminalEntry &e = m_all.at(m_visible.at(row));
        const QString text = (hexMode && !e.raw.isEmpty()) ? hexString(e) : e.msgText;
        if (re.match(text).hasMatch())
            matches.append(e.entryIndex);
    }
    return matches;
}

QVariantList TerminalModel::rowsForEntryIndices(const QVariantList &entryIndices) const
{
    // 輸入與 m_visible 的 entryIndex 皆遞增 → 單趟雙指針,免去逐筆二分
    QVariantList result;
    result.reserve(entryIndices.size());
    int row = 0;
    for (const QVariant &v : entryIndices) {
        const int target = v.toInt();
        while (row < m_visible.size() && m_all.at(m_visible.at(row)).entryIndex < target)
            ++row;
        result.append(row < m_visible.size() && m_all.at(m_visible.at(row)).entryIndex == target
                      ? row : -1);
    }
    return result;
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

QVariantList TerminalModel::allEntries() const
{
    QVariantList result;
    result.reserve(m_all.size());
    for (const TerminalEntry &e : m_all)
        result.append(entryToMap(e));
    return result;
}

QVariantList TerminalModel::tailEntries(int count) const
{
    const int n = qBound(0, count, static_cast<int>(m_all.size()));
    QVariantList result;
    result.reserve(n);
    for (int i = m_all.size() - n; i < m_all.size(); ++i)
        result.append(entryToMap(m_all.at(i)));
    return result;
}

QVariantList TerminalModel::visibleEntries() const
{
    QVariantList result;
    result.reserve(m_visible.size());
    for (int idx : m_visible)
        result.append(entryToMap(m_all.at(idx)));
    return result;
}

int TerminalModel::rowForEntryIndex(int entryIndex) const
{
    // m_visible 依 row 遞增,對應的 entryIndex 亦嚴格遞增 → 可二分搜尋
    int lo = 0, hi = m_visible.size() - 1;
    while (lo <= hi) {
        const int mid = (lo + hi) / 2;
        const int v = m_all.at(m_visible.at(mid)).entryIndex;
        if (v == entryIndex)
            return mid;
        if (v < entryIndex)
            lo = mid + 1;
        else
            hi = mid - 1;
    }
    return -1;
}

QString TerminalModel::computeHlColor(const TerminalEntry &e) const
{
    if (m_hlKeywords.isEmpty())
        return QString();
    const QString text = ((m_hlHexMode && !e.raw.isEmpty()) ? hexString(e) : e.msgText).toLower();
    for (const HlKeyword &kw : m_hlKeywords) {
        if (text.contains(kw.textLower))
            return kw.color;
    }
    return QString();
}

void TerminalModel::setHighlightKeywords(const QVariantList &keywords, bool hexMode)
{
    m_hlKeywords.clear();
    for (const QVariant &v : keywords) {
        const QVariantMap kw = v.toMap();
        if (!kw.value(QStringLiteral("enabled")).toBool())
            continue;
        const QString text = kw.value(QStringLiteral("text")).toString().toLower();
        if (text.isEmpty())
            continue;
        m_hlKeywords.append({ text, kw.value(QStringLiteral("color")).toString() });
    }
    m_hlHexMode = hexMode;

    for (TerminalEntry &e : m_all)
        e.hlColor = computeHlColor(e);

    emit highlightKeywordsChanged();
}

QVariantList TerminalModel::highlightMarkers() const
{
    QVariantList result;
    for (int row = 0; row < m_visible.size(); ++row) {
        const TerminalEntry &e = m_all.at(m_visible.at(row));
        if (!e.hlColor.isEmpty()) {
            result.append(QVariantMap{
                { QStringLiteral("row"),   row },
                { QStringLiteral("color"), e.hlColor },
            });
        }
    }
    return result;
}

QVariantList TerminalModel::entryIndicesInRange(int loRow, int hiRow) const
{
    QVariantList result;
    // 空 model 防禦:trim 可能把 m_visible 清空,拖曳選取中的 stale row 會打進來
    if (m_visible.isEmpty())
        return result;
    const int lo = qBound(0, loRow, m_visible.size() - 1);
    const int hi = qBound(0, hiRow, m_visible.size() - 1);
    if (hi < lo)
        return result;
    for (int row = lo; row <= hi; ++row)
        result.append(m_all.at(m_visible.at(row)).entryIndex);
    return result;
}

QString TerminalModel::hexString(const TerminalEntry &e)
{
    return e.raw.isEmpty() ? QString()
                           : QString::fromLatin1(e.raw.toHex(' ')).toUpper();
}

QVariantMap TerminalModel::entryToMap(const TerminalEntry &e)
{
    return {
        { QStringLiteral("timestamp"),  e.timestamp },
        { QStringLiteral("msgText"),    e.msgText },
        { QStringLiteral("hexData"),    hexString(e) },
        { QStringLiteral("type"),       e.type },
        { QStringLiteral("entryIndex"), e.entryIndex },
    };
}
