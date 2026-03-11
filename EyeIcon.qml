import QtQuick

Canvas {
    id: root
    width: 14
    height: 14

    property bool open: true
    property color iconColor: "white"

    onOpenChanged: requestPaint()
    onIconColorChanged: requestPaint()

    onPaint: {
        var ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)

        var cx = width  / 2
        var cy = height / 2

        ctx.strokeStyle = iconColor
        ctx.fillStyle   = iconColor
        ctx.lineCap     = "round"
        ctx.lineJoin    = "round"

        if (open) {
            // ── Eye outline (almond shape) ──────────────────────────
            ctx.lineWidth = 1.3
            ctx.beginPath()
            ctx.moveTo(1.5, cy)
            ctx.quadraticCurveTo(cx, 2.5,           width - 1.5, cy)
            ctx.quadraticCurveTo(cx, height - 2.5,  1.5,         cy)
            ctx.stroke()

            // ── Pupil ───────────────────────────────────────────────
            ctx.beginPath()
            ctx.arc(cx, cy, 2.2, 0, Math.PI * 2)
            ctx.fill()

        } else {
            // ── Closed lid arc ──────────────────────────────────────
            ctx.lineWidth = 1.3
            ctx.beginPath()
            ctx.moveTo(1.5, cy + 1)
            ctx.quadraticCurveTo(cx, cy - 4, width - 1.5, cy + 1)
            ctx.stroke()

            // ── Lashes ──────────────────────────────────────────────
            ctx.lineWidth = 1.0
            ctx.beginPath()
            ctx.moveTo(cx - 3.5, cy + 2);  ctx.lineTo(cx - 4.5, cy + 5)
            ctx.moveTo(cx,       cy + 2.5); ctx.lineTo(cx,       cy + 5.5)
            ctx.moveTo(cx + 3.5, cy + 2);  ctx.lineTo(cx + 4.5, cy + 5)
            ctx.stroke()
        }
    }
}
