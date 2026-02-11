import QtQuick
import QtQuick.Controls

CheckBox {
    id: control

    property color accentColor: "#00ff88"

    font.family: "Consolas"
    font.pixelSize: 11
    font.letterSpacing: 1
    font.capitalization: Font.AllUppercase

    indicator: Rectangle {
        implicitWidth: 18
        implicitHeight: 18
        x: control.leftPadding
        y: parent.height / 2 - height / 2
        color: control.checked ? control.accentColor : "transparent"
        border.color: control.checked ? control.accentColor : "#3a3a4a"
        border.width: 1

        Text {
            anchors.centerIn: parent
            text: "✓"
            font.pixelSize: 12
            font.bold: true
            color: "#0a0a0f"
            visible: control.checked
        }

        // Subtle glow when checked
        Rectangle {
            anchors.fill: parent
            anchors.margins: -2
            color: "transparent"
            border.color: control.accentColor
            border.width: 1
            opacity: control.checked ? 0.3 : 0
        }
    }

    contentItem: Text {
        text: control.text
        font: control.font
        color: control.checked ? control.accentColor : "#6b7280"
        verticalAlignment: Text.AlignVCenter
        leftPadding: control.indicator.width + control.spacing
    }
}
