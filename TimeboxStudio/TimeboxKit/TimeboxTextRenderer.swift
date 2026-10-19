import Foundation
#if canImport(CoreText)
import CoreText
import CoreGraphics
#endif

public struct TimeboxRenderedText: Sendable {
    public let animation: TimeboxAnimation
    public let fontName: String
    public let rasterWidth: Int
}

/// System fixed-pitch font, 12px white on black; one pixel leftward every 100ms.
public enum TimeboxTextRenderer {
    public static func render(_ text: String) throws -> TimeboxRenderedText {
        #if canImport(CoreText)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.utf16.count <= 1024 else {
            throw TimeboxAnimationError.invalid("Text must be nonempty and at most 1024 UTF-16 units (host input limit).")
        }
        guard let font = CTFontCreateUIFontForLanguage(.userFixedPitch, 12, nil) else {
            throw TimeboxAnimationError.invalid("No system fixed-pitch font is available.")
        }
        var unsupported: [String] = []
        for scalar in text.unicodeScalars {
            let units = Array(String(scalar).utf16)
            var glyphs = [CGGlyph](repeating: 0, count: units.count)
            let supported = CTFontGetGlyphsForCharacters(font, units, &glyphs, units.count)
            if !supported || glyphs.contains(0) || CharacterSet.controlCharacters.contains(scalar) {
                unsupported.append("\(scalar) (U+\(String(scalar.value, radix: 16).uppercased()))")
            }
        }
        guard unsupported.isEmpty else {
            throw TimeboxAnimationError.invalid("The resolved font \(CTFontCopyPostScriptName(font)) does not support: " + Array(Set(unsupported)).sorted().joined(separator: ", "))
        }
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1)
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        let bounds = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
        let advance = CTLineGetTypographicBounds(line, nil, nil, nil)
        let left = min(0, floor(bounds.minX))
        let widthValue = ceil(max(advance, bounds.maxX) - left)
        guard widthValue.isFinite, widthValue > 0, widthValue <= 2016, bounds.height <= 16 else {
            throw TimeboxAnimationError.invalid("Text exceeds the raster/frame envelope; shorten it. Text is never truncated or adapted.")
        }
        let width = Int(widthValue)
        var rgba = [UInt8](repeating: 0, count: width * 16 * 4)
        guard let context = CGContext(data: &rgba, width: width, height: 16, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw TimeboxAnimationError.invalid("Cannot rasterize text.")
        }
        context.setShouldAntialias(false)
        context.setShouldSmoothFonts(false)
        context.textPosition = CGPoint(x: -left, y: floor((16 - bounds.height) / 2) - bounds.minY)
        CTLineDraw(line, context)
        // Bitmap rows already match the top-left pixel order used by the image encoder.
        var frames: [TimeboxAnimationFrame] = []
        for offset in 0...(width + 16) {
            var image = PixelFrame()
            for y in 0..<16 { for x in 0..<16 {
                let sourceX = x + offset - 16
                guard sourceX >= 0, sourceX < width else { continue }
                let source = (y * width + sourceX) * 4
                image.pixels[y * 16 + x] = PixelRGB(red: rgba[source], green: rgba[source + 1], blue: rgba[source + 2])
            } }
            frames.append(try TimeboxAnimationFrame(image: image, durationMilliseconds: 100))
        }
        let animation = try TimeboxAnimation(frames: frames)
        // Text has no lossy adaptation contract: fail before sending if it cannot fit.
        _ = try TimeboxAnimationEncoder.prepare(animation)
        return TimeboxRenderedText(animation: animation, fontName: CTFontCopyPostScriptName(font) as String, rasterWidth: width)
        #else
        throw TimeboxAnimationError.invalid("Text rasterization requires CoreText and CoreGraphics.")
        #endif
    }
}
