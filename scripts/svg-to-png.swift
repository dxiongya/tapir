#!/usr/bin/env swift
import Cocoa

let args = CommandLine.arguments
guard args.count >= 4 else {
    FileHandle.standardError.write(Data("usage: svg-to-png.swift <input.svg> <size> <output.png>\n".utf8))
    exit(1)
}

let inPath = args[1]
guard let size = Int(args[2]), size > 0 else {
    FileHandle.standardError.write(Data("size must be a positive integer\n".utf8))
    exit(1)
}
let outPath = args[3]

guard let image = NSImage(contentsOfFile: inPath) else {
    FileHandle.standardError.write(Data("failed to load \(inPath)\n".utf8))
    exit(1)
}

let pixelSize = NSSize(width: size, height: size)
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: size,
    pixelsHigh: size,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    FileHandle.standardError.write(Data("failed to allocate bitmap\n".utf8))
    exit(1)
}
bitmap.size = pixelSize

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSGraphicsContext.current?.imageInterpolation = .high
image.draw(in: NSRect(origin: .zero, size: pixelSize),
           from: .zero,
           operation: .copy,
           fraction: 1.0)
NSGraphicsContext.restoreGraphicsState()

guard let data = bitmap.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("failed to encode PNG\n".utf8))
    exit(1)
}

let outURL = URL(fileURLWithPath: outPath)
try? FileManager.default.createDirectory(at: outURL.deletingLastPathComponent(),
                                         withIntermediateDirectories: true)
do {
    try data.write(to: outURL)
    print("wrote \(outPath) (\(data.count) bytes)")
} catch {
    FileHandle.standardError.write(Data("write failed: \(error)\n".utf8))
    exit(1)
}
