import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// ---------------------------------------------------------------------------
// FreeMic icon generator.
// Draws a broadcast-style headset (over-ear headphones + boom mic) — evoking
// both "耳机" (headphones) and the "Mic" in FreeMic — on a fresh mint→teal
// squircle. Renders the macOS .iconset PNGs plus a monochrome menu-bar
// template image.
// ---------------------------------------------------------------------------

func makeContext(_ px: Int) -> CGContext {
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8,
                        bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.setAllowsAntialiasing(true)
    return ctx
}

func writePNG(_ ctx: CGContext, _ path: String) {
    let img = ctx.makeImage()!
    let url = URL(fileURLWithPath: path)
    let dst = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dst, img, nil)
    CGImageDestinationFinalize(dst)
}

// Continuous-ish rounded rect path.
func roundedRect(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    return CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

// Draw the headset into `rect` (the art area). `white` = fill/stroke color.
// `boldScale` thickens strokes for small template renders.
func drawHeadset(_ ctx: CGContext, rect: CGRect, color: CGColor, boldScale: CGFloat = 1.0) {
    let s = rect.width            // art box is square
    let ox = rect.minX, oy = rect.minY
    func P(_ ux: CGFloat, _ uy: CGFloat) -> CGPoint { CGPoint(x: ox + ux * s, y: oy + uy * s) }
    func L(_ u: CGFloat) -> CGFloat { u * s }

    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.setStrokeColor(color)
    ctx.setFillColor(color)

    let cx: CGFloat = 0.5, cy: CGFloat = 0.60, Rmid: CGFloat = 0.295
    let bandW = L(0.095 * boldScale)

    // Headband arc (clockwise over the top, from 198° to -18°).
    func rad(_ d: CGFloat) -> CGFloat { d * .pi / 180 }
    let bandPath = CGMutablePath()
    bandPath.addArc(center: P(cx, cy), radius: L(Rmid),
                    startAngle: rad(198), endAngle: rad(-18), clockwise: true)
    ctx.addPath(bandPath)
    ctx.setLineWidth(bandW)
    ctx.strokePath()

    // Ear cups (vertical pills) at the band ends.
    let La = rad(198), Ra = rad(-18)
    let Lx = cx + Rmid * cos(La), Ly = cy + Rmid * sin(La)
    let Rx = cx + Rmid * cos(Ra), Ry = cy + Rmid * sin(Ra)
    let cupW: CGFloat = 0.185, cupH: CGFloat = 0.275
    func cup(_ centerX: CGFloat, _ topY: CGFloat) {
        let w = L(cupW), h = L(cupH)
        let r = CGRect(x: ox + centerX * s - w/2, y: oy + topY * s - h, width: w, height: h)
        ctx.addPath(roundedRect(r, w/2))
        ctx.fillPath()
    }
    cup(Lx, Ly + 0.055)   // left cup hangs below the band end
    cup(Rx, Ry + 0.055)

    // Boom mic: thin arm curving from the right cup toward mouth-center,
    // ending in a rounded mic capsule (drawn as a thick round-capped pill).
    let cupBottomR = CGPoint(x: ox + Rx * s, y: oy + (Ry + 0.055 - cupH) * s)
    let boom = CGMutablePath()
    boom.move(to: CGPoint(x: cupBottomR.x, y: cupBottomR.y + L(0.03)))
    boom.addCurve(to: P(0.555, 0.205),
                  control1: P(0.80, 0.16),
                  control2: P(0.70, 0.165))
    ctx.addPath(boom)
    ctx.setLineWidth(L(0.05 * boldScale))
    ctx.strokePath()

    // Mic capsule (pill) at the boom tip.
    let capsule = CGMutablePath()
    capsule.move(to: P(0.555, 0.205))
    capsule.addLine(to: P(0.37, 0.20))
    ctx.addPath(capsule)
    ctx.setLineWidth(L(0.092))
    ctx.strokePath()
}

// ---- App icon (gradient tile + white headset) ----
func renderAppIcon(_ px: Int, _ path: String) {
    let ctx = makeContext(px)
    let size = CGFloat(px)
    ctx.clear(CGRect(x: 0, y: 0, width: size, height: size))

    // Rounded tile with a small margin (native macOS look).
    let margin = size * 0.085
    let tile = CGRect(x: margin, y: margin, width: size - 2*margin, height: size - 2*margin)
    let radius = tile.width * 0.2235
    let tilePath = roundedRect(tile, radius)

    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.clip()
    let cs = CGColorSpaceCreateDeviceRGB()
    let grad = CGGradient(colorsSpace: cs, colors: [
        CGColor(red: 0.45, green: 0.89, blue: 0.76, alpha: 1),   // top mint
        CGColor(red: 0.05, green: 0.70, blue: 0.64, alpha: 1),   // bottom teal
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(grad,
        start: CGPoint(x: tile.minX, y: tile.maxY),
        end: CGPoint(x: tile.maxX, y: tile.minY), options: [])
    ctx.restoreGState()

    // Headset in white with a soft shadow.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -size*0.006),
                  blur: size*0.014,
                  color: CGColor(red: 0, green: 0.15, blue: 0.13, alpha: 0.22))
    let art = CGRect(x: margin + tile.width*0.10, y: margin + tile.height*0.10,
                     width: tile.width*0.80, height: tile.height*0.80)
    drawHeadset(ctx, rect: art, color: CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.restoreGState()

    writePNG(ctx, path)
}

// ---- Menu-bar template (black headset on transparent) ----
func renderMenuTemplate(_ px: Int, _ path: String) {
    let ctx = makeContext(px)
    let size = CGFloat(px)
    ctx.clear(CGRect(x: 0, y: 0, width: size, height: size))
    let pad = size * 0.04
    let art = CGRect(x: pad, y: pad, width: size - 2*pad, height: size - 2*pad)
    drawHeadset(ctx, rect: art,
                color: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
                boldScale: 1.15)
    writePNG(ctx, path)
}

// ---- Drive ----
let buildDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let iconset = buildDir + "/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)

let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, px) in sizes { renderAppIcon(px, "\(iconset)/\(name).png") }

renderAppIcon(1024, buildDir + "/preview.png")
renderMenuTemplate(54, buildDir + "/menu.png")
renderMenuTemplate(180, buildDir + "/menu_preview.png")
print("done")
