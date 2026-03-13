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
        ctx.lineCap = "round"
        ctx.lineJoin = "round"

        // ── Handle ──────────────────────────────────────────────
        // Goes from upper-right (14,1) to where it meets the broom head top edge (6.3,8.7)
        ctx.lineWidth = 1.4
        ctx.beginPath()
        ctx.moveTo(14, 1)
        ctx.lineTo(6.3, 8.7)
        ctx.stroke()

        // ── Broom head ──────────────────────────────────────────
        // Rotated 45° (PI/4) so the long axis is perpendicular to the 45° handle
        // translate(5, 10) places the center; rect(-4.5,-1.8,9,3.6) is the brush body
        ctx.save()
        ctx.translate(5, 10)
        ctx.rotate(Math.PI / 4)

        // Outer outline
        ctx.lineWidth = 1.1
        ctx.beginPath()
        ctx.rect(-4.5, -1.8, 9, 3.6)
        ctx.stroke()

        // Bristle divider lines (vertical in rotated space)
        ctx.lineWidth = 0.65
        ctx.beginPath()
        ctx.moveTo(-2.2, -1.8); ctx.lineTo(-2.2, 1.8)
        ctx.moveTo( 0.3, -1.8); ctx.lineTo( 0.3, 1.8)
        ctx.moveTo( 2.8, -1.8); ctx.lineTo( 2.8, 1.8)
        ctx.stroke()

        ctx.restore()

        // ── Sparkle × marks (lower-left, outside the brush) ────
        ctx.lineWidth = 0.8
        ctx.beginPath()
        ctx.moveTo(1.0, 12.0); ctx.lineTo(2.0, 13.0)
        ctx.moveTo(2.0, 12.0); ctx.lineTo(1.0, 13.0)
        ctx.moveTo(3.0, 14.0); ctx.lineTo(4.0, 15.0)
        ctx.moveTo(4.0, 14.0); ctx.lineTo(3.0, 15.0)
        ctx.stroke()
    }
}
