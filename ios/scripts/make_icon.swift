// Draws the app icon: a vinyl record seen at a shallow angle, with a burst of
// light exploding from behind it, on the game's deep green.
//
//   swift ios/scripts/make_icon.swift ios/PopQuiz/Assets.xcassets/AppIcon.appiconset/icon.png
//
// Output is a 1024x1024 opaque PNG (the App Store rejects icons with alpha).

import AppKit
import CoreGraphics
import Foundation

let size = 1024
let S = CGFloat(size)
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
// Work top-down, like a screen.
ctx.translateBy(x: 0, y: S)
ctx.scaleBy(x: 1, y: -1)

func gradient(_ stops: [(CGFloat, CGColor)]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: stops.map(\.1) as CFArray, locations: stops.map(\.0))!
}

// Background: deep green, lighter where the burst is.
ctx.drawLinearGradient(
    gradient([(0, rgb(0.10, 0.27, 0.19)), (1, rgb(0.02, 0.08, 0.05))]),
    start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: S), options: [])

let burst = CGPoint(x: 590, y: 420)

// Soft glow around the burst.
ctx.drawRadialGradient(
    gradient([(0, rgb(1.0, 0.86, 0.35, 0.85)), (0.35, rgb(1.0, 0.72, 0.12, 0.35)), (1, rgb(1.0, 0.72, 0.12, 0))]),
    startCenter: burst, startRadius: 0, endCenter: burst, endRadius: 520, options: [])

// The explosion: a jagged star, rays of uneven length.
func star(center: CGPoint, points: Int, inner: CGFloat, outer: [CGFloat], twist: CGFloat) -> CGPath {
    let path = CGMutablePath()
    for i in 0..<(points * 2) {
        let angle = twist + CGFloat(i) * .pi / CGFloat(points)
        let r = i % 2 == 0 ? outer[(i / 2) % outer.count] : inner
        let p = CGPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r)
        if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
    }
    path.closeSubpath()
    return path
}

let outerRays: [CGFloat] = [430, 330, 400, 300, 450, 340, 380, 310, 420, 350, 395, 320, 440, 335]
ctx.saveGState()
ctx.addPath(star(center: burst, points: 14, inner: 165, outer: outerRays, twist: -0.12))
ctx.clip()
ctx.drawRadialGradient(
    gradient([(0, rgb(1.0, 0.98, 0.78)), (0.35, rgb(1.0, 0.85, 0.3)), (0.75, rgb(1.0, 0.68, 0.1)), (1, rgb(0.95, 0.5, 0.08))]),
    startCenter: burst, startRadius: 0, endCenter: burst, endRadius: 450, options: [.drawsAfterEndLocation])
ctx.restoreGState()

// A hotter inner star.
let innerRays: [CGFloat] = [250, 190, 235, 175, 260, 200, 225, 185, 245, 195]
ctx.saveGState()
ctx.addPath(star(center: burst, points: 10, inner: 110, outer: innerRays, twist: 0.2))
ctx.clip()
ctx.drawRadialGradient(
    gradient([(0, rgb(1, 1, 0.95)), (0.5, rgb(1.0, 0.93, 0.6)), (1, rgb(1.0, 0.82, 0.25))]),
    startCenter: burst, startRadius: 0, endCenter: burst, endRadius: 260, options: [.drawsAfterEndLocation])
ctx.restoreGState()

// Sparks flying out: small four-point stars.
func sparkle(_ c: CGPoint, _ r: CGFloat, _ color: CGColor) {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: c.x, y: c.y - r))
    p.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + r * 0.15, y: c.y - r * 0.15))
    p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x + r * 0.15, y: c.y + r * 0.15))
    p.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - r * 0.15, y: c.y + r * 0.15))
    p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x - r * 0.15, y: c.y - r * 0.15))
    ctx.addPath(p)
    ctx.setFillColor(color)
    ctx.fillPath()
}
for (x, y, r) in [(905.0, 150.0, 34.0), (220.0, 205.0, 26.0), (860.0, 470.0, 20.0), (330.0, 110.0, 16.0), (700.0, 95.0, 18.0), (160.0, 420.0, 14.0)] {
    sparkle(CGPoint(x: x, y: y), r, rgb(1, 0.95, 0.7))
}

// The record, tipped back to a shallow angle and turned a little.
let center = CGPoint(x: 500, y: 690)
let rx: CGFloat = 430, ry: CGFloat = 150, thickness: CGFloat = 26
ctx.saveGState()
ctx.translateBy(x: center.x, y: center.y)
ctx.rotate(by: -0.14)

func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ a: CGFloat, _ b: CGFloat) -> CGRect {
    CGRect(x: cx - a, y: cy - b, width: a * 2, height: b * 2)
}

// A second light behind the record: a warm glow all the way round the disc
// that lifts it off the dark background.
func outline() -> CGPath {
    let p = CGMutablePath()
    p.addEllipse(in: ellipse(0, 0, rx, ry))
    p.addEllipse(in: ellipse(0, thickness, rx, ry))
    p.addRect(CGRect(x: -rx, y: 0, width: rx * 2, height: thickness))
    return p
}
for (blur, alpha) in [(110.0, 0.75), (55.0, 0.85), (22.0, 0.9)] as [(CGFloat, CGFloat)] {
    ctx.setShadow(offset: .zero, blur: blur, color: rgb(1.0, 0.78, 0.2, alpha))
    ctx.addPath(outline())
    ctx.setFillColor(rgb(0.02, 0.02, 0.02))
    ctx.fillPath(using: .winding)
}
ctx.setShadow(offset: .zero, blur: 0, color: nil)
// Edge of the disc.
ctx.setFillColor(rgb(0.02, 0.02, 0.02))
ctx.fillEllipse(in: ellipse(0, thickness, rx, ry))
ctx.setShadow(offset: .zero, blur: 0, color: nil)
ctx.fill(CGRect(x: -rx, y: 0, width: rx * 2, height: thickness))
// Top face: black vinyl with a faint sheen.
ctx.saveGState()
ctx.addEllipse(in: ellipse(0, 0, rx, ry))
ctx.clip()
ctx.drawLinearGradient(
    gradient([(0, rgb(0.17, 0.17, 0.16)), (0.5, rgb(0.05, 0.05, 0.05)), (1, rgb(0.11, 0.11, 0.1))]),
    start: CGPoint(x: -rx, y: -ry), end: CGPoint(x: rx, y: ry), options: [])
// Grooves.
ctx.setLineWidth(2)
var k: CGFloat = 0.96
while k > 0.36 {
    ctx.setStrokeColor(rgb(0.32, 0.32, 0.3, k.truncatingRemainder(dividingBy: 0.08) < 0.04 ? 0.5 : 0.25))
    ctx.strokeEllipse(in: ellipse(0, 0, rx * k, ry * k))
    k -= 0.035
}
// Light catching the grooves, from the burst behind.
ctx.drawRadialGradient(
    gradient([(0, rgb(1.0, 0.85, 0.4, 0.4)), (1, rgb(1.0, 0.85, 0.4, 0))]),
    startCenter: CGPoint(x: 150, y: -90), startRadius: 0, endCenter: CGPoint(x: 150, y: -90), endRadius: 260, options: [])
ctx.restoreGState()

// Label.
let labelA = rx * 0.33, labelB = ry * 0.33
ctx.saveGState()
ctx.addEllipse(in: ellipse(0, 0, labelA, labelB))
ctx.clip()
ctx.drawLinearGradient(
    gradient([(0, rgb(1.0, 0.85, 0.32)), (1, rgb(0.95, 0.65, 0.1))]),
    start: CGPoint(x: 0, y: -labelB), end: CGPoint(x: 0, y: labelB), options: [])
ctx.setStrokeColor(rgb(0.1, 0.3, 0.2, 0.55))
ctx.setLineWidth(5)
ctx.strokeEllipse(in: ellipse(0, 0, labelA * 0.72, labelB * 0.72))
ctx.restoreGState()
// Spindle hole.
ctx.setFillColor(rgb(0.03, 0.03, 0.03))
ctx.fillEllipse(in: ellipse(0, 0, 13, 13 * ry / rx))
ctx.restoreGState()

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
