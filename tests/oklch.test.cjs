// Run: node tests/oklch.test.cjs. Also usable by the offline swatch renderer.
const fs = require('fs');
const vm = require('vm');
const assert = require('assert');
const path = require('path');
const ctx = { Qt: { rgba: (r, g, b, a) => ({r, g, b, a}) }, Math: Object.create(Math) };
vm.createContext(ctx);
vm.runInContext(fs.readFileSync(path.join(__dirname, '../oklch.js'), 'utf8').replace(/^\.pragma library\s*/, ''), ctx);
function color(hex) {
    const n = parseInt(hex.replace('#', ''), 16);
    return {r: (n >> 16 & 255)/255, g: (n >> 8 & 255)/255, b: (n & 255)/255, a: 1};
}
function hueDistance(a, b) { return Math.abs(Math.atan2(Math.sin(a-b), Math.cos(a-b))) * 180/Math.PI; }
function run() {
    const blue = color('#7aa2f7'), gold = color('#e0af68');
    const darkFg = color('#c0caf5'), lightFg = color('#24283b');
    for (const hex of ['#7aa2f7','#e0af68','#c0caf5','#24283b','#ffffff','#000000','#ff0000','#00ff00','#0000ff']) {
        const source = color(hex), lch = ctx.toLch(source), out = ctx.fromLch(lch.L,lch.C,lch.h,source.a);
        for (const k of ['r','g','b']) assert(Math.abs(source[k]-out[k]) < 0.001, `round trip ${hex} ${k}`);
        for (const fg of [darkFg,lightFg]) {
            for (const output of [ctx.dim(source),ctx.hover(source,fg)]) {
                for (const k of ['r','g','b','a']) assert(Number.isFinite(output[k]) && output[k]>=0 && output[k]<=1);
            }
        }
    }
    const blueTint = ctx.hover(blue,darkFg);
    const drift = hueDistance(ctx.toLch(blue).h,ctx.toLch(blueTint).h);
    assert(drift < 0.1, 'blue stays at its OKLCH hue, including gamut mapping');
    const yellowDelta = ctx.toLch(ctx.hover(gold,darkFg)).L - ctx.toLch(gold).L;
    assert(Math.abs(yellowDelta-0.04)<0.0001, 'gold hover has only the requested +0.04 perceptual L');
    assert(ctx.toLch(ctx.dim(lightFg)).L > ctx.toLch(lightFg).L, 'dark text dims lighter');
    assert(ctx.toLch(ctx.dim(darkFg)).L < ctx.toLch(darkFg).L, 'light text dims darker');
    const oldDim = color('#7c829e'); // approximate Qt.darker(#c0caf5, 1.55)
    assert(Math.abs(ctx.toLch(ctx.dim(darkFg)).L-ctx.toLch(oldDim).L)<0.04, 'Tokyo Night remains near old dim lightness');
    assert(ctx.hover(blue,darkFg).a===0.18);
    const transparent = {...blue,a:0}; assert(ctx.hover(transparent,darkFg).a===0);
    const original = ctx.cubeRoot(-0.125); ctx.Math.cbrt=undefined;
    assert(Math.abs(ctx.cubeRoot(-0.125)-original)<1e-12, 'signed cbrt fallback');
    delete ctx.Math.cbrt;
    const newTheme = ctx.hover(gold,lightFg);
    assert(Math.abs(newTheme.r-blueTint.r)>0.01, 'new theme recalculates, no stale cache');
    const panel=fs.readFileSync(path.join(__dirname,'../Panel.qml'),'utf8');
    assert(panel.includes('bar ? Oklch.hover(Commons.Color.accent, foreground) : "transparent"'));
    assert(panel.includes('row.isActive ? Commons.Color.accent : root.foreground'));
    console.log(`PASS: round trips, gamut/alpha, fallback, theme recalculation, live bindings; blue hue drift ${drift.toFixed(5)} degrees; gold hover delta L ${yellowDelta.toFixed(5)}; light dim moves lighter.`);
}
if(require.main===module) run();
module.exports={ctx,color,hueDistance};
