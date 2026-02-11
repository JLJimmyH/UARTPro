import QtQuick
import QtQuick.Controls

Button {
    id: control

    property color accentColor: "#00ff88"
    property bool glowing: false

    font.family: "Consolas"
    font.pixelSize: 12
    font.letterSpacing: 2
    font.capitalization: Font.AllUppercase

    contentItem: Text {
        text: control.text
        font: control.font
        color: control.down ? "#0a0a0f" : (control.enabled ? control.accentColor : "#3a3a4a")
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    background: Item {
        implicitHeight: 38
        implicitWidth: 120

        // Outer glow
        Rectangle {
            anchors.fill: parent
            anchors.margins: -3
            color: "transparent"
            border.color: control.accentColor
            border.width: 2
            opacity: (control.hovered || control.glowing) && control.enabled ? 0.15 : 0
            Behavior on opacity { NumberAnimation { duration: 150 } }
        }

        // Mid glow
        Rectangle {
            anchors.fill: parent
            anchors.margins: -1
            color: "transparent"
            border.color: control.accentColor
            border.width: 1
            opacity: (control.hovered || control.glowing) && control.enabled ? 0.3 : 0
            Behavior on opacity { NumberAnimation { duration: 150 } }
        }

        // Main background
        Rectangle {
            anchors.fill: parent
            color: control.down ? control.accentColor : "transparent"
            border.color: {
                if (!control.enabled) return "#2a2a3a"
                if (control.hovered || control.glowing) return control.accentColor
                return "#3a3a4a"
            }
            border.width: (control.hovered || control.glowing) ? 2 : 1
            Behavior on border.color { ColorAnimation { duration: 150 } }
        }
    }
}
