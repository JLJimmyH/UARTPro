import QtQuick
import QtQuick.Controls

ComboBox {
    id: control

    property color accentColor: "#00ff88"
    property color cardColor: "#12121a"
    property color borderColor: "#2a2a3a"
    property color fgColor: "#e0e0e0"
    property color bgColor: "#0a0a0f"
    property color mutedFgColor: "#6b7280"
    property color mutedColor: "#1c1c2e"
    // Popup reparents to the (unscaled) window overlay, so its body must be
    // scaled manually to match the contentRoot scale transform.
    property real uiScale: 1.0

    font.family: "Consolas"
    font.pixelSize: 12

    background: Rectangle {
        implicitHeight: 36
        color: control.cardColor
        border.color: control.activeFocus || control.popup.visible ? control.accentColor : control.borderColor
        border.width: 1
        Behavior on border.color { ColorAnimation { duration: 150 } }
    }

    contentItem: Item {
        implicitHeight: 36
        // ">" prefix
        Text {
            id: prefixText
            text: ">"
            font.family: "Consolas"
            font.pixelSize: 14
            font.bold: true
            color: control.accentColor
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            anchors.left: prefixText.right
            anchors.leftMargin: 6
            anchors.right: parent.right
            anchors.rightMargin: 28
            anchors.verticalCenter: parent.verticalCenter
            text: control.displayText || "SELECT..."
            font: control.font
            color: control.displayText ? control.accentColor : control.mutedFgColor
            elide: Text.ElideRight
        }
    }

    indicator: Text {
        text: control.popup.visible ? "\u25B2" : "\u25BC"
        font.family: "Consolas"
        font.pixelSize: 8
        color: control.mutedFgColor
        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
    }

    delegate: ItemDelegate {
        width: control.width * control.uiScale
        height: 32 * control.uiScale
        highlighted: control.highlightedIndex === index

        contentItem: Text {
            text: modelData !== undefined ? modelData : model[control.textRole]
            font.family: "Consolas"
            font.pixelSize: 12 * control.uiScale
            color: parent.highlighted ? control.bgColor : control.fgColor
            verticalAlignment: Text.AlignVCenter
            leftPadding: 10 * control.uiScale
            elide: Text.ElideRight
        }
        background: Rectangle {
            color: parent.highlighted ? control.accentColor : (parent.hovered ? control.mutedColor : "transparent")
        }
    }

    popup: Popup {
        y: control.height
        width: control.width * control.uiScale
        padding: 1

        contentItem: ListView {
            implicitHeight: Math.min(contentHeight, 200 * control.uiScale)
            model: control.delegateModel
            clip: true
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        }
        background: Rectangle {
            color: control.cardColor
            border.color: control.accentColor
            border.width: 1
        }
    }
}
