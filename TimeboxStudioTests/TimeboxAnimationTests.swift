import XCTest
@testable import TimeboxKit
import TimeboxCLIKit

final class TimeboxAnimationTests: XCTestCase {
    let fixture = "docs/validation/fixtures/animation-disposal.gif"
    func testIndependentRedFrameFixtureAndChunkLengths() throws {
        let red = PixelFrame(fill: PixelRGB(red: 255, green: 0, blue: 0))
        let animation = try TimeboxAnimation(frames: [TimeboxAnimationFrame(image: red, durationMilliseconds: 100)])
        let upload = try TimeboxAnimationEncoder.prepare(animation)
        let expected = try String(contentsOfFile: "docs/validation/fixtures/animation-solid-red.hex").split(whereSeparator: \.isWhitespace).map { UInt8($0, radix: 16)! }
        XCTAssertEqual(upload.packets, [Data(expected)])
        let many = try TimeboxAnimation(frames: Array(repeating: animation.frames[0], count: 1000))
        let chunks = try TimeboxAnimationEncoder.prepare(many).packets
        XCTAssertEqual(chunks.count, 210)
        XCTAssertEqual(chunks.first?[4], 0x10); XCTAssertEqual(chunks.first?[5], 0xa4) // 42000 bytes, LE16
        for (index, packet) in chunks.enumerated() {
            XCTAssertEqual(packet[6], UInt8(index))
            XCTAssertEqual(packet.count, 210) // 200 bytes + 4 command header + 6 envelope
        }
    }
    func testExplicitAdaptationPreservesDurationAndRejectsUnfitInputs() throws {
        let image = PixelFrame(fill: PixelRGB(red: 255, green: 0, blue: 0))
        let frame = try TimeboxAnimationFrame(image: image, durationMilliseconds: 100)
        let large = try TimeboxAnimation(frames: Array(repeating: frame, count: 1300))
        XCTAssertThrowsError(try TimeboxAnimationEncoder.prepare(large))
        let adapted = try TimeboxAnimationEncoder.prepare(large, adapt: true)
        XCTAssertTrue(adapted.adapted); XCTAssertLessThan(adapted.effectiveFrames, 1300)
        XCTAssertEqual(adapted.effectiveMilliseconds, 130000)
        let long = try TimeboxAnimation(frames: [TimeboxAnimationFrame(image: image, durationMilliseconds: 65536)])
        XCTAssertThrowsError(try TimeboxAnimationEncoder.prepare(long))
        let split = try TimeboxAnimationEncoder.prepare(long, adapt: true)
        XCTAssertEqual(split.effectiveFrames, 2); XCTAssertEqual(split.effectiveMilliseconds, 65536)
        XCTAssertThrowsError(try TimeboxAnimation(frames: []))
        XCTAssertThrowsError(try TimeboxAnimationFrame(image: image, durationMilliseconds: 0))
    }
    func testGIFPartialPatchesDisposalTransparencyAndDelays() throws {
        let animation = try GIFAnimationLoader.load(path: fixture, resize: .stretch)
        XCTAssertEqual(animation.frames.map(\.durationMilliseconds), [100,200,300,100])
        let red = PixelRGB(red: 255, green: 0, blue: 0), green = PixelRGB(red: 0, green: 255, blue: 0)
        let blue = PixelRGB(red: 0, green: 0, blue: 255), black = PixelRGB(red: 0, green: 0, blue: 0)
        XCTAssertEqual(animation.frames[0].image.pixels[5*16+5], red)
        XCTAssertEqual(animation.frames[1].image.pixels[5*16+5], green)
        XCTAssertEqual(animation.frames[2].image.pixels[5*16+5], black) // disposal 2 cleared patch
        XCTAssertEqual(animation.frames[2].image.pixels[9*16+9], blue)
        XCTAssertEqual(animation.frames[3].image.pixels[9*16+9], red) // disposal 3 restored prior canvas
        let raw = try Data(contentsOf: URL(fileURLWithPath: fixture))
        XCTAssertThrowsError(try GIFAnimationLoader.decode(raw.dropLast()))
        XCTAssertThrowsError(try GIFAnimationLoader.decode(Data("not gif".utf8)))
    }
    func testInitialPartialFrameUsesDeclaredOpaqueBackground() throws {
        var bytes = Data("GIF89a".utf8)
        bytes.append(contentsOf: [4,0,4,0,0x81,1,0, 0,0,0, 255,0,0, 0,255,0, 0,0,255])
        bytes.append(contentsOf: [0x21,0xf9,4,4,10,0,0,0,0x2c,1,0,1,0,1,0,1,0,0,2,2,0x54,0x01,0,0x3b])
        let animation = try GIFAnimationLoader.decode(bytes, resize: .stretch)
        XCTAssertEqual(animation.frames[0].image.pixels[0], PixelRGB(red:255,green:0,blue:0))
        XCTAssertEqual(animation.frames[0].image.pixels[5*16+5], PixelRGB(red:0,green:255,blue:0))
    }
    func testResizePoliciesKeepNearestNeighborAndCenteredPadding() throws {
        let red = [UInt8](arrayLiteral:255,0,0,255), green = [UInt8](arrayLiteral:0,255,0,255)
        let pixels = red + green + red + green // 4x1
        let fit = try GIFAnimationLoader.resizeRGBA(pixels, width: 4, height: 1, policy: .fit)
        XCTAssertEqual(fit.pixels[0], PixelRGB(red:0,green:0,blue:0))
        XCTAssertEqual(fit.pixels[6*16], PixelRGB(red:255,green:0,blue:0))
        let stretch = try GIFAnimationLoader.resizeRGBA(pixels, width:4,height:1,policy:.stretch)
        XCTAssertEqual(stretch.pixels[0], PixelRGB(red:255,green:0,blue:0))
        let fill = try GIFAnimationLoader.resizeRGBA(pixels,width:4,height:1,policy:.fill)
        XCTAssertEqual(fill.pixels[0], PixelRGB(red:0,green:255,blue:0))
        XCTAssertEqual(fill.pixels[15], PixelRGB(red:255,green:0,blue:0))
    }
    func testCLIOrderedUploadsInvalidInputAndFailureDoNotRetryPartialUpload() throws {
        let h = CommandHarness()
        XCTAssertEqual(h.run(["animation", fixture,"--address","AA:BB:CC:DD:EE:01","--json"]),0)
        let expected = try TimeboxAnimationEncoder.prepare(GIFAnimationLoader.load(path: fixture)).packets
        XCTAssertEqual(h.transport.packets, expected)
        XCTAssertTrue(h.rawStdout.contains("source_frames")); XCTAssertTrue(h.rawStdout.contains("sent"))
        let invalid = CommandHarness()
        XCTAssertEqual(invalid.run(["animation",fixture,"--resize","invalid"]),2)
        XCTAssertTrue(invalid.transport.connections.isEmpty)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".gif")
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try Data(contentsOf: URL(fileURLWithPath: fixture))
        // Fixture header + global table is 25 bytes. Duplicate the complete four-frame body.
        var multi = Data(source.prefix(25)); multi.append(source[25..<(source.count - 1)])
        multi.append(source[25..<(source.count - 1)]); multi.append(0x3b)
        try multi.write(to: root)
        let failure = CommandHarness(); failure.transport.failOnWriteNumber = 2
        XCTAssertEqual(failure.run(["animation",root.path,"--address","AA:BB:CC:DD:EE:01"]),1)
        XCTAssertEqual(failure.transport.connections.count,1)
        XCTAssertEqual(failure.transport.packets.count,1)
        XCTAssertTrue(failure.stderr.joined().contains("partial"))
        let repl = CommandHarness();repl.input = ["animation " + fixture,"quit"]
        XCTAssertEqual(repl.run(["repl","--address","AA:BB:CC:DD:EE:01"]),0)
        XCTAssertEqual(repl.transport.packets,expected)
    }
}
