import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
import ImageIO
#endif

public enum TimeboxResizePolicy: String, CaseIterable, Sendable { case fit, fill, stretch }

/// Parses GIF container/disposal explicitly; ImageIO only decodes each standalone patch.
/// Host limits prevent a small compressed input from causing unbounded allocation.
public enum GIFAnimationLoader {
    public static func load(path: String, resize: TimeboxResizePolicy = .fit) throws -> TimeboxAnimation {
        let url = URL(fileURLWithPath: path)
        guard let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 16 * 1024 * 1024 else {
            throw TimeboxAnimationError.invalid("GIF input exceeds the 16 MiB host file limit.")
        }
        return try decode(Data(contentsOf: url), resize: resize)
    }

    public static func decode(_ data: Data, resize: TimeboxResizePolicy = .fit) throws -> TimeboxAnimation {
        #if canImport(CoreGraphics)
        guard data.count <= 16 * 1024 * 1024 else { throw TimeboxAnimationError.invalid("GIF exceeds the 16 MiB host file limit.") }
        var parser = GIFParser(data)
        let header = try parser.take(13)
        guard ["GIF87a", "GIF89a"].contains(String(bytes: header.prefix(6), encoding: .ascii) ?? "") else {
            throw TimeboxAnimationError.invalid("Animation input must be a GIF file.")
        }
        let width = Int(header[6]) | Int(header[7]) << 8
        let height = Int(header[8]) | Int(header[9]) << 8
        guard width > 0, height > 0, width <= 4096, height <= 4096, width * height <= 4_194_304 else {
            throw TimeboxAnimationError.invalid("GIF canvas exceeds the host 4096-axis / 4-megapixel limit.")
        }
        let global = header[10] & 0x80 != 0 ? try parser.take(3 * (1 << Int((header[10] & 7) + 1))) : []
        var canvas = [UInt8](repeating: 0, count: width * height * 4)
        var frames: [TimeboxAnimationFrame] = []
        var control: [UInt8] = [0, 0, 0, 0]
        var processedPixels = 0
        var ended = false
        while !parser.atEnd {
            let marker = try parser.byte()
            if marker == 0x3b { ended = true; break }
            if marker == 0x21 {
                let label = try parser.byte()
                if label == 0xf9 {
                    guard try parser.byte() == 4 else { throw GIFParser.error }
                    control = try parser.take(4)
                    guard try parser.byte() == 0 else { throw GIFParser.error }
                    guard ((control[0] >> 2) & 7) <= 3 else { throw TimeboxAnimationError.invalid("Reserved GIF disposal mode is unsupported.") }
                    guard control[0] & 2 == 0 else { throw TimeboxAnimationError.invalid("GIF user-input timing cannot be reproduced on the device.") }
                } else if label == 1 {
                    throw TimeboxAnimationError.invalid("GIF plain-text extensions are unsupported; rasterize them first.")
                } else { _ = try parser.blocks() }
                continue
            }
            guard marker == 0x2c, frames.count < 2048 else { throw GIFParser.error }
            var descriptor = try parser.take(9)
            let x = Int(descriptor[0]) | Int(descriptor[1]) << 8
            let y = Int(descriptor[2]) | Int(descriptor[3]) << 8
            let w = Int(descriptor[4]) | Int(descriptor[5]) << 8
            let h = Int(descriptor[6]) | Int(descriptor[7]) << 8
            guard w > 0, h > 0, x + w <= width, y + h <= height else { throw GIFParser.error }
            processedPixels += width * height
            guard processedPixels <= 67_108_864 else { throw TimeboxAnimationError.invalid("GIF exceeds the host 64-megapixel decoded-work limit.") }
            let local = descriptor[8] & 0x80 != 0 ? try parser.take(3 * (1 << Int((descriptor[8] & 7) + 1))) : []
            guard !local.isEmpty || !global.isEmpty else { throw GIFParser.error }
            let codeSize = try parser.byte()
            guard (2...8).contains(codeSize) else { throw GIFParser.error }
            let compressed = try parser.blocks()
            // Decode just the patch: reset descriptor offset and logical screen to patch dimensions.
            var patchHeader = header
            patchHeader[6] = UInt8(w & 255); patchHeader[7] = UInt8(w >> 8)
            patchHeader[8] = UInt8(h & 255); patchHeader[9] = UInt8(h >> 8)
            descriptor[0] = 0; descriptor[1] = 0; descriptor[2] = 0; descriptor[3] = 0
            var standalone = Data(patchHeader)
            standalone.append(contentsOf: global)
            standalone.append(contentsOf: [0x21, 0xf9, 4])
            standalone.append(contentsOf: control)
            standalone.append(contentsOf: [0, 0x2c])
            standalone.append(contentsOf: descriptor)
            standalone.append(contentsOf: local)
            standalone.append(codeSize)
            standalone.append(contentsOf: compressed); standalone.append(0x3b)
            guard let source = CGImageSourceCreateWithData(standalone as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw GIFParser.error }
            var patch = [UInt8](repeating: 0, count: w * h * 4)
            guard let context = CGContext(data: &patch, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw GIFParser.error }
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            if frames.isEmpty {
                let index = Int(header[11])
                let transparent = control[0] & 1 != 0 && control[3] == header[11]
                if !transparent, global.count >= index * 3 + 3 {
                    let background = Array(global[index * 3..<(index * 3 + 3)]) + [UInt8(255)]
                    for pixel in 0..<(width * height) { canvas.replaceSubrange((pixel * 4)..<(pixel * 4 + 4), with: background) }
                }
            }
            let before = canvas
            for py in 0..<h {
                for px in 0..<w {
                    let src = (py * w + px) * 4
                    let dst = ((y + py) * width + x + px) * 4
                    if patch[src + 3] != 0 { canvas.replaceSubrange(dst..<(dst + 4), with: patch[src..<(src + 4)]) }
                }
            }
            let delay = (Int(control[1]) | Int(control[2]) << 8) * 10
            frames.append(try TimeboxAnimationFrame(image: resizeRGBA(canvas, width: width, height: height, policy: resize), durationMilliseconds: delay == 0 ? 100 : delay))
            let disposal = (control[0] >> 2) & 7
            if disposal == 2 {
                // Restore logical-screen background; a transparent background is composited onto black.
                let backgroundIndex = Int(header[11])
                let transparent = control[0] & 1 != 0 && control[3] == header[11]
                let background: [UInt8] = !transparent && global.count >= backgroundIndex * 3 + 3
                    ? Array(global[backgroundIndex * 3..<(backgroundIndex * 3 + 3)]) + [255] : [0, 0, 0, 0]
                for py in 0..<h { for px in 0..<w {
                    let dst = ((y + py) * width + x + px) * 4
                    canvas.replaceSubrange(dst..<(dst + 4), with: background)
                } }
            } else if disposal == 3 { canvas = before }
            control = [0, 0, 0, 0]
        }
        guard ended, !frames.isEmpty else { throw GIFParser.error }
        return try TimeboxAnimation(frames: frames)
        #else
        throw TimeboxAnimationError.invalid("GIF decoding requires ImageIO and CoreGraphics.")
        #endif
    }

    static func resizeRGBA(_ rgba: [UInt8], width: Int, height: Int, policy: TimeboxResizePolicy) throws -> PixelFrame {
        var result = PixelFrame()
        let scale = policy == .fill ? max(16.0 / Double(width), 16.0 / Double(height)) : min(16.0 / Double(width), 16.0 / Double(height))
        let outW = policy == .stretch ? 16 : max(1, Int((Double(width) * scale).rounded()))
        let outH = policy == .stretch ? 16 : max(1, Int((Double(height) * scale).rounded()))
        let left = outW <= 16 ? (16 - outW) / 2 : -((outW - 16) / 2)
        let top = outH <= 16 ? (16 - outH) / 2 : -((outH - 16) / 2)
        for y in 0..<16 { for x in 0..<16 {
            let ox = x - left, oy = y - top
            guard ox >= 0, oy >= 0, ox < outW, oy < outH else { continue }
            let sx = min(width - 1, ox * width / outW), sy = min(height - 1, oy * height / outH)
            let offset = (sy * width + sx) * 4
            // Premultiplied RGB already composites transparency against black.
            result.pixels[y * 16 + x] = PixelRGB(red: rgba[offset], green: rgba[offset + 1], blue: rgba[offset + 2])
        } }
        return result
    }
}

private struct GIFParser {
    let bytes: [UInt8]
    var offset = 0
    init(_ data: Data) { bytes = Array(data) }
    static var error: TimeboxAnimationError { .invalid("Malformed, unsupported or excessive GIF data.") }
    var atEnd: Bool { offset == bytes.count }
    mutating func byte() throws -> UInt8 { try take(1)[0] }
    mutating func take(_ count: Int) throws -> [UInt8] {
        guard count >= 0, offset + count <= bytes.count else { throw Self.error }
        defer { offset += count }; return Array(bytes[offset..<(offset + count)])
    }
    mutating func blocks() throws -> [UInt8] {
        var result: [UInt8] = []
        while true {
            let count = try byte(); result.append(count)
            if count == 0 { return result }
            result.append(contentsOf: try take(Int(count)))
        }
    }
}
