#!/usr/bin/env swift

import Foundation
import ImageIO

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write(Data("Usage: generate-icns.swift input.png output.icns\n".utf8))
    exit(2)
}

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])

guard let source = CGImageSourceCreateWithURL(inputURL as CFURL, nil) else {
    FileHandle.standardError.write(Data("Could not read \(inputURL.path)\n".utf8))
    exit(1)
}

let representations: [(type: String, size: Int)] = [
    ("icp4", 16),
    ("ic11", 32),
    ("icp5", 32),
    ("ic12", 64),
    ("ic07", 128),
    ("ic13", 256),
    ("ic08", 256),
    ("ic14", 512),
    ("ic09", 512),
    ("ic10", 1024)
]

func bigEndianData(_ value: UInt32) -> Data {
    var encoded = value.bigEndian
    return Data(bytes: &encoded, count: MemoryLayout<UInt32>.size)
}

var encodedPNGs: [Int: Data] = [:]
for size in Set(representations.map(\.size)) {
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: size
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
        FileHandle.standardError.write(Data("Could not render \(size)x\(size) icon\n".utf8))
        exit(1)
    }
    let pngData = NSMutableData()
    guard let pngDestination = CGImageDestinationCreateWithData(
        pngData,
        "public.png" as CFString,
        1,
        nil
    ) else {
        FileHandle.standardError.write(Data("Could not create \(size)x\(size) PNG\n".utf8))
        exit(1)
    }
    CGImageDestinationAddImage(pngDestination, image, nil)
    guard CGImageDestinationFinalize(pngDestination) else {
        FileHandle.standardError.write(Data("Could not encode \(size)x\(size) PNG\n".utf8))
        exit(1)
    }
    encodedPNGs[size] = pngData as Data
}

var chunks = Data()
for representation in representations {
    guard let png = encodedPNGs[representation.size] else { continue }
    chunks.append(Data(representation.type.utf8))
    chunks.append(bigEndianData(UInt32(png.count + 8)))
    chunks.append(png)
}

var icns = Data("icns".utf8)
icns.append(bigEndianData(UInt32(chunks.count + 8)))
icns.append(chunks)

do {
    try icns.write(to: outputURL, options: .atomic)
} catch {
    FileHandle.standardError.write(Data("Could not write \(outputURL.path): \(error.localizedDescription)\n".utf8))
    exit(1)
}
