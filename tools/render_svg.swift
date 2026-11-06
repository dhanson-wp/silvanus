#!/usr/bin/env swift
// Renders an SVG or PNG to a square PNG with real transparency. No Xcode needed.
//   swift tools/render_svg.swift <in.svg|in.png> <out.png> <pixels>...
// With several sizes, give an output pattern containing {px}, e.g. out-{px}.png.
// The artwork fills the whole canvas, so the source carries its own margin.
// (Adapted from Capture Director's tools/render_icon.swift.)
import AppKit

let args = CommandLine.arguments
guard args.count >= 4 else {
    FileHandle.standardError.write(Data("usage: render_svg.swift <in> <out.png> <pixels>...\n".utf8))
    exit(2)
}
let input = URL(fileURLWithPath: args[1])
guard let image = NSImage(contentsOf: input) else {
    FileHandle.standardError.write(Data("could not read \(args[1])\n".utf8))
    exit(1)
}
for token in args.dropFirst(3) {
    guard let pixels = Int(token), pixels > 0 else { exit(2) }
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    NSColor.clear.set()
    NSRect(x: 0, y: 0, width: pixels, height: pixels).fill(using: .copy)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    let path = args[2].replacingOccurrences(of: "{px}", with: String(pixels))
    try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}
