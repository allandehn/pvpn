import QtQuick
import QtTest
import "../oklch.js" as Oklch

TestCase {
    name: "LiveOklchTints"
    property color foreground: "#c0caf5"
    property color accent: "#7aa2f7"
    property bool hasBar: true
    readonly property color dimmed: Oklch.dim(foreground)
    readonly property color overlay: hasBar ? Oklch.hover(accent, foreground) : "transparent"

    function test_liveTheme() {
        var initial = overlay.toString()
        foreground = "#24283b"
        accent = "#e0af68"
        verify(overlay.toString() !== initial)
        verify(Oklch.toLch(dimmed).L > Oklch.toLch(foreground).L)
        verify(Math.abs(overlay.a - 0.18) < 0.005)
        hasBar = false
        compare(overlay.a, 0)
        hasBar = true
        verify(overlay.a > 0)
    }
    function test_qtBaseline() {
        // Qt.darker is HSV-based, not HSL; don't invent a purple shift.
        var oldDim = Qt.darker(Qt.rgba(192/255,202/255,245/255,1), 1.55)
        var newDim = Oklch.dim(Qt.rgba(192/255,202/255,245/255,1))
        verify(Math.abs(Oklch.toLch(oldDim).L - Oklch.toLch(newDim).L) < 0.04)
    }
}
