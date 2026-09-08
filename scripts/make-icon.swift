import AppKit

let output = CommandLine.arguments[1]
let size = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let bounds = NSRect(x: 36, y: 36, width: 952, height: 952)
let background = NSBezierPath(roundedRect: bounds, xRadius: 212, yRadius: 212)
NSGradient(starting: NSColor(red: 0.10, green: 0.20, blue: 0.24, alpha: 1), ending: NSColor(red: 0.04, green: 0.10, blue: 0.15, alpha: 1))!.draw(in: background, angle: -65)
let colors = [NSColor(red: 0.90, green: 0.59, blue: 0.43, alpha: 1), NSColor(red: 0.35, green: 0.80, blue: 0.68, alpha: 1), NSColor(red: 0.53, green: 0.65, blue: 0.96, alpha: 1)]
for (index, height) in [290.0, 440.0, 570.0].enumerated() {
    let x = 230.0 + Double(index) * 205.0
    let rect = NSRect(x: x, y: 230, width: 148, height: height)
    let path = NSBezierPath(roundedRect: rect, xRadius: 53, yRadius: 53)
    NSGradient(starting: colors[index], ending: colors[index].withAlphaComponent(0.7))!.draw(in: path, angle: -90)
}
image.unlockFocus()
let representation = NSBitmapImageRep(data: image.tiffRepresentation!)!
try representation.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
