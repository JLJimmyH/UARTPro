import QtQuick
import QtQuick.Controls

ComboBox {
    id: control

    property color accentColor: "#00ff88"

    font.family: "Consolas"
    font.pixelSize: 12

    background: Rectangle {
        implicitHeight: 36
        color: "#12121a"
        border.color: control.activeFocus || control.popup.visible ? control.accentColor : "#2a2a3a"
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
            color: control.displayText ? control.accentColor : "#6b7280"
            elide: Text.ElideRight
        }
    }

    indicator: Text {
        text: control.popup.visible ? "▲" : "▼"
        font.family: "Consolas"
        font.pixelSize: 8
        color: "#6b7280"
        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
    }

    delegate: ItemDelegate {
        width: control.width
        height: 32
        highlighted: control.highlightedIndex === index

        contentItem: Text {
            text: modelData !== undefined ? modelData : model[control.textRole]
            font.family: "Consolas"
            font.pixelSize: 12
            color: parent.highlighted ? "#0a0a0f" : "#e0e0e0"
            verticalAlignment: Text.AlignVCenter
            leftPadding: 10
            elide: Text.ElideRight
        }
        background: Rectangle {
            color: parent.highlighted ? control.accentColor : (parent.hovered ? "#1c1c2e" : "transparent")
        }
    }

    popup: Popup {
        y: control.height
        width: control.width
        padding: 1

        contentItem: ListView {
            implicitHeight: Math.min(contentHeight, 200)
            model: control.delegateModel
            clip: true
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        }
        background: Rectangle {
            color: "#12121a"
            border.color: control.accentColor
            border.width: 1
        }
    }
}
