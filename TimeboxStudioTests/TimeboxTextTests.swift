import XCTest
import TimeboxKit
import TimeboxCLIKit
#if canImport(CoreText)
import CoreText
#endif

final class TimeboxTextTests: XCTestCase {
    func testDeterministicMonospacedRasterAndOnePixelLeftwardFrames() throws {
        let rendered = try TimeboxTextRenderer.render("F")
        XCTAssertFalse(rendered.fontName.isEmpty)
        XCTAssertEqual(rendered.animation.frames.count, rendered.rasterWidth + 17)
        XCTAssertTrue(rendered.animation.frames.allSatisfy { $0.durationMilliseconds == 100 })
        XCTAssertEqual(rendered.animation.frames.first?.image, PixelFrame())
        XCTAssertEqual(rendered.animation.frames.last?.image, PixelFrame())
        let first = rendered.animation.frames[16].image
        let next = rendered.animation.frames[17].image
        for y in 0..<16 { for x in 0..<15 { XCTAssertEqual(next.pixels[y*16+x],first.pixels[y*16+x+1]) } }
        let rows = (0..<16).map { y in first.pixels[(y*16)..<(y*16+16)].filter { $0.red > 0 }.count }
        let ink = rows.filter { $0 > 0 }
        XCTAssertGreaterThan(ink.count,5)
        XCTAssertGreaterThan(ink.first!,ink.last!,"F must be upright, with a wider top than its stem: \(rows)")
        XCTAssertTrue(first.pixels.allSatisfy { $0.red == $0.green && $0.green == $0.blue && [0,255].contains(Int($0.red)) })
        XCTAssertEqual(try TimeboxTextRenderer.render("F").animation, rendered.animation)
    }
    func testQuotesUnicodeGlyphPolicyAndBounds() throws {
        XCTAssertNoThrow(try TimeboxTextRenderer.render("Café \"oui\""))
        for text in ["", "   ", "\n", "hello\nworld", "\u{10ffff}", String(repeating:"W",count:1025)] {
            XCTAssertThrowsError(try TimeboxTextRenderer.render(text),text)
        }
        XCTAssertThrowsError(try TimeboxTextRenderer.render(String(repeating:"W",count:300)))
    }
    func testCLIUsesAnimationPacketsAndReportsResolvedFont() throws {
        let h = CommandHarness()
        XCTAssertEqual(h.run(["text","Hello \"world\"","--address","AA:BB:CC:DD:EE:01","--json"]),0)
        let rendered = try TimeboxTextRenderer.render("Hello \"world\"")
        XCTAssertEqual(h.transport.packets,try TimeboxAnimationEncoder.prepare(rendered.animation).packets)
        XCTAssertTrue(h.rawStdout.contains("font"));XCTAssertTrue(h.rawStdout.contains("sent"))
        XCTAssertTrue(h.stderr.joined().contains(rendered.fontName))
        let invalid = CommandHarness()
        XCTAssertEqual(invalid.run(["text","\u{10ffff}","--address","AA:BB:CC:DD:EE:01"]),1)
        XCTAssertTrue(invalid.transport.connections.isEmpty)
        XCTAssertEqual(invalid.run(["text","hello","--adapt"]),2)
    }
    func testREPLQuotedTextPreservesLiteralQuotesAndUsesExistingTarget() throws {
        let h = CommandHarness()
        h.input = ["text \"Hello \\\"world\\\"\"","quit"]
        XCTAssertEqual(h.run(["repl","--address","AA:BB:CC:DD:EE:01"]),0)
        let rendered = try TimeboxTextRenderer.render("Hello \"world\"")
        XCTAssertEqual(h.transport.packets,try TimeboxAnimationEncoder.prepare(rendered.animation).packets)
        XCTAssertEqual(h.transport.connections.count,1)
    }
}
