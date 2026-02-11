import QtQuick
import QtQuick.Controls

TextField {
    id: control

    property color accentColor: "#00ff88"
    property color cardColor: "#12121a"
    property color borderColor: "#2a2a3a"
    property color bgColor: "#0a0a0f"
    property color mutedFgColor: "#6b7280"

    font.family: "Consolas"
    font.pixelSize: 13
    color: accentColor
    selectionColor: accentColor
    selectedTextColor: bgColor
    placeholderTextColor: mutedFgColor
    leftPadding: 28

    background: Rectangle {
        implicitHeight: 38
        color: control.cardColor
        border.color: control.activeFocus ? control.accentColor : control.borderColor
        border.width: 1
        Behavior on border.color { ColorAnimation { duration: 150 } }

        // ">" prefix
        Text {
            text: ">"
            font.family: "Consolas"
            font.pixelSize: 14
            font.bold: true
            color: control.accentColor
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
        }

        // Focus glow
        Rectangle {
            anchors.fill: parent
            anchors.margins: -2
            color: "transparent"
            border.color: control.accentColor
            border.width: 1
            opacity: control.activeFocus ? 0.2 : 0
            Behavior on opacity { NumberAnimation { duration: 150 } }
        }
    }
}
