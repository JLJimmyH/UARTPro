import QtQuick

Canvas {
    id: root
    width: 16
    height: 16

    property color iconColor: "white"

    onIconColorChanged: requestPaint()

    onPaint: {
        var ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)

        ctx.strokeStyle = iconColor
        ctx.lineWidth = 1.3
        ctx.lineCap = "round"
        ctx.lineJoin = "round"

        // ── Folder outline (tab on top-left) ────────────────────
        ctx.beginPath()
        ctx.moveTo(2, 3.6)      // tab top-left (also top of left side)
        ctx.lineTo(6, 3.6)      // tab top-right
        ctx.lineTo(7.2, 5.4)    // slope down to body top edge
        ctx.lineTo(14, 5.4)     // body top-right
        ctx.lineTo(14, 12.8)    // body bottom-right
        ctx.lineTo(2, 12.8)     // body bottom-left
        ctx.closePath()         // left side back up to start
        ctx.stroke()

        // ── Lid divider line ────────────────────────────────────
        ctx.lineWidth = 0.8
        ctx.beginPath()
        ctx.moveTo(2, 7.2)
        ctx.lineTo(14, 7.2)
        ctx.stroke()
    }
}
