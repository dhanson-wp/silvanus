#!/usr/bin/env swift
// Paints rectangles over a 2x window capture in one flat color, so tools/compare.sh can
// leave out the parts that differ from the reference by design (design/KIT.md "Compare").
// Usage: swift tools/compare-mask.swift in.png out.png x y w h [x y w h ...]
// Rectangles are in points from the top left. Prints how many pixels it covered.

import AppKit
import CoreGraphics
import Foundation

let args = Array(CommandLine.arguments.dropFirst())
guard args.count >= 6, (args.count - 2) % 4 == 0 else {
    print("usage: swift tools/compare-mask.swift in.png out.png x y w h [x y w h ...]")
    exit(1)
}
guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[0]) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    print("cannot read \(args[0])")
    exit(1)
}
let width = image.width, height = image.height
let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
// Magenta: no part of either window uses it.
ctx.setFillColor(CGColor(red: 1, green: 0, blue: 1, alpha: 1))
var covered = Set<Int>()
let numbers = args.dropFirst(2).compactMap(Double.init)
for i in stride(from: 0, to: numbers.count, by: 4) {
    let x = Int(numbers[i] * 2), y = Int(numbers[i + 1] * 2), w = Int(numbers[i + 2] * 2), h = Int(numbers[i + 3] * 2)
    // The context's origin is the bottom left.
    ctx.fill(CGRect(x: x, y: height - y - h, width: w, height: h))
    for py in max(0, y)..<min(height, y + h) {
        for px in max(0, x)..<min(width, x + w) { covered.insert(py * width + px) }
    }
}
let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[1]))
print("masked \(covered.count) of \(width * height) pixels")
