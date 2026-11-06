.pragma library

// Björn Ottosson's sRGB <-> OKLab matrices. Colours enter/leave as QML colours.
// No theme cache: Panel's bindings own the derived colours and track live inputs.
function clamp(x) { return Math.max(0, Math.min(1, x)) }
function cubeRoot(x) {
    return Math.cbrt ? Math.cbrt(x) : (x < 0 ? -1 : 1) * Math.pow(Math.abs(x), 1 / 3)
}
function linear(x) { return x <= 0.04045 ? x / 12.92 : Math.pow((x + 0.055) / 1.055, 2.4) }
function srgb(x) { return x <= 0.0031308 ? 12.92 * x : 1.055 * Math.pow(x, 1 / 2.4) - 0.055 }
function toLch(color) {
    var r = linear(color.r), g = linear(color.g), b = linear(color.b)
    var l = cubeRoot(0.4122214708*r + 0.5363325363*g + 0.0514459929*b)
    var m = cubeRoot(0.2119034982*r + 0.6806995451*g + 0.1073969566*b)
    var s = cubeRoot(0.0883024619*r + 0.2817188376*g + 0.6299787005*b)
    var L = 0.2104542553*l + 0.7936177850*m - 0.0040720468*s
    var a = 1.9779984951*l - 2.4285922050*m + 0.4505937099*s
    var bb = 0.0259040371*l + 0.7827717662*m - 0.8086757660*s
    return { L: L, C: Math.sqrt(a*a + bb*bb), h: Math.atan2(bb, a) }
}
function linearRgb(L, C, h) {
    var a = C * Math.cos(h), b = C * Math.sin(h)
    var l = L + 0.3963377774*a + 0.2158037573*b
    var m = L - 0.1055613458*a - 0.0638541728*b
    var s = L - 0.0894841775*a - 1.2914855480*b
    l = l*l*l; m = m*m*m; s = s*s*s
    return [4.0767416621*l - 3.3077115913*m + 0.2309699292*s,
            -1.2684380046*l + 2.6097574011*m - 0.3413193965*s,
            -0.0041960863*l - 0.7034186147*m + 1.7076147010*s]
}
function inGamut(rgb) {
    return rgb.every(function(x) { return x >= -0.000001 && x <= 1.000001 })
}
function fromLch(L, C, h, alpha) {
    L = clamp(L)
    var rgb = linearRgb(L, C, h)
    // Only out-of-gamut tints need this bounded search. Reduce chroma rather than
    // clipping individual channels (which would shift hue). Never per frame.
    if (!inGamut(rgb)) {
        var low = 0, high = C
        for (var i = 0; i < 12; ++i) {
            var mid = (low + high) / 2
            if (inGamut(linearRgb(L, mid, h))) low = mid
            else high = mid
        }
        rgb = linearRgb(L, low, h)
    }
    return Qt.rgba(clamp(srgb(rgb[0])), clamp(srgb(rgb[1])), clamp(srgb(rgb[2])), clamp(alpha))
}
function dim(foreground) {
    var c = toLch(foreground)
    // Secondary text moves toward mid-lightness: light text down, dark text up.
    // -0.22 is close to Qt.darker(..., 1.55) on Tokyo Night, without HSV drift.
    return fromLch(c.L + (c.L >= 0.6 ? -0.22 : 0.22), c.C * 0.85, c.h, foreground.a)
}
function hover(accent, foreground) {
    var c = toLch(accent)
    // Light text implies a dark surface; nudge the overlay toward that text.
    var delta = toLch(foreground).L >= 0.6 ? 0.04 : -0.04
    return fromLch(c.L + delta, c.C, c.h, accent.a * 0.18)
}
