import XCTest
import TimeboxKit
import TimeboxCLIKit
@testable import TimeboxBluetooth

final class TimeboxTextStreamTests: XCTestCase {
    private let address = "AA:BB:CC:DD:EE:01"

    func testMiniRasterPreservesEveryOnePixelPositionBeyondNativeBuffer() throws {
        let raster = try TimeboxTextRenderer.render("F", model: .mini)
        let stream = try TimeboxTextStream("F", model: .mini)
        XCTAssertGreaterThan(stream.packets.count, 12)
        XCTAssertEqual(stream.packets.count, raster.rasterWidth + 12)
        XCTAssertEqual(raster.animation.frames.first?.image, PixelFrame(model: .mini))
        XCTAssertEqual(raster.animation.frames.last?.image, PixelFrame(model: .mini))
        let first = raster.animation.frames[11].image
        let next = raster.animation.frames[12].image
        for y in 0..<11 { for x in 0..<10 {
            XCTAssertEqual(next.pixels[y * 11 + x], first.pixels[y * 11 + x + 1])
        } }
        let rows = (0..<11).map { y in first.pixels[(y*11)..<(y*11+11)].filter { $0.red > 0 }.count }.filter { $0 > 0 }
        XCTAssertGreaterThan(rows.count, 3)
        XCTAssertGreaterThan(rows.first!, rows.last!, "F must stay upright in the smaller viewport")
        XCTAssertEqual(stream.packets, try raster.animation.frames.map { try TimeboxMiniEncoder.encode(.image($0.image)) })
        XCTAssertThrowsError(try TimeboxAnimationEncoder.prepare(raster.animation, model: .mini))
    }

    func testCLIStreamFormatsOneCompletePassWithoutReconnectOrTimingDrift() throws {
        let expected = try TimeboxTextStream("Hi", model: .mini)
        for format in ["--json", "--yaml"] {
            let h = CommandHarness()
            h.transport.writeSeconds = 0.04
            XCTAssertEqual(h.run(["text", "Hi", "--stream", "--address", address, "--model", "mini", format]), 0, h.stderr.joined())
            XCTAssertEqual(h.transport.packets, expected.packets)
            XCTAssertEqual(h.transport.connections.count, 1)
            XCTAssertFalse(h.transport.isConnected)
            XCTAssertEqual(h.transport.waits.count, expected.packets.count + 1)
            XCTAssertTrue(h.transport.waits.dropFirst().allSatisfy { (59...61).contains($0) })
            XCTAssertEqual(h.transport.uptime, 0.15 + Double(expected.durationMilliseconds) / 1000, accuracy: 0.03)
            XCTAssertTrue(h.rawStdout.contains("host_stream"))
            XCTAssertTrue(h.rawStdout.contains("completed"))
            XCTAssertFalse(h.rawStdout.contains("readback_matches"))
        }
        let slow = CommandHarness(); slow.transport.writeSeconds = 0.15
        XCTAssertEqual(slow.run(["text", "Hi", "--stream", "--address", address, "--model", "mini"]), 0)
        XCTAssertEqual(slow.transport.packets, expected.packets)
        XCTAssertEqual(slow.transport.waits, [150], "late frames must not be skipped or followed by a catch-up burst")
    }

    func testHostStreamDoesNotInheritNativeAnimationBufferLimitOnEvo() throws {
        let text = String(repeating: "W", count: 200)
        XCTAssertThrowsError(try TimeboxTextRenderer.render(text))
        let stream = try TimeboxTextStream(text)
        XCTAssertGreaterThan(stream.packets.count, 1000)
        XCTAssertLessThanOrEqual(stream.packets.count, 2048)
    }

    func testInvalidRequestsAndImplicitMiniTextNeverConnect() {
        let cases: [[String]] = [
            ["text", "Hi", "--address", address, "--model", "mini"],
            ["text", "\u{10ffff}", "--stream", "--address", address, "--model", "mini"],
            ["text", "Hi", "--stream", "--device", "missing"],
            ["text", "Hi", "--stream", "--adapt"],
            ["time", "sync", "--stream"], ["config", "--stream"], ["list", "--stream"],
            ["repl", "--stream"]
        ]
        for arguments in cases {
            let h = CommandHarness()
            XCTAssertNotEqual(h.run(arguments), 0, arguments.joined(separator: " "))
            XCTAssertTrue(h.transport.connections.isEmpty)
            XCTAssertTrue(h.transport.packets.isEmpty)
        }
        let h = CommandHarness()
        XCTAssertEqual(h.run(["text", "Hi", "--address", address, "--model", "mini"]), 1)
        XCTAssertTrue(h.stderr.joined().contains("--stream"))
    }

    func testREPLStreamingQuotesAndModelSwitchKeepExistingTargetRules() throws {
        let h = CommandHarness()
        h.configuration = .init(defaultName: "mini", devices: ["mini": .init(mac: address, model: .mini), "evo": .init(mac: "AA:BB:CC:DD:EE:02", model: .evo)])
        h.input = ["text --stream \"Hi \\\"Mini\\\" --stream\"", "target evo", "text \"Hello\"", "quit"]
        XCTAssertEqual(h.run(["repl"]), 0, h.stderr.joined())
        let mini = try TimeboxTextStream("Hi \"Mini\" --stream", model: .mini)
        let evo = try TimeboxAnimationEncoder.prepare(TimeboxTextRenderer.render("Hello").animation)
        XCTAssertEqual(h.transport.packets, mini.packets + evo.packets)
        XCTAssertEqual(h.transport.connections.count, 2)
        XCTAssertEqual(Array(h.transport.writeTargets.prefix(mini.packets.count)), Array(repeating: address, count: mini.packets.count))
    }

    func testPartialWriteStopsWithoutRetryOrFalseCompletion() {
        let h = CommandHarness(); h.transport.failOnWriteNumber = 2
        XCTAssertEqual(h.run(["text", "Hi", "--stream", "--address", address, "--model", "mini", "--json"]), 1)
        XCTAssertEqual(h.transport.connections.count, 1)
        XCTAssertEqual(h.transport.packets.count, 1)
        XCTAssertFalse(h.transport.isConnected)
        XCTAssertTrue(h.rawStdout.contains("write_failed"))
        XCTAssertFalse(h.rawStdout.contains("completed"))
        XCTAssertTrue(h.stderr.joined().contains("1 of"))
    }

    func testREPLStreamRejectsSelectorFlagsWithoutDisturbingTarget() {
        let h = CommandHarness()
        h.input = ["text --stream --device missing \"Hi\"", "target", "quit"]
        XCTAssertEqual(h.run(["repl", "--address", address, "--model", "mini"]), 0)
        XCTAssertTrue(h.transport.packets.isEmpty)
        XCTAssertEqual(h.transport.connections.count, 1)
        XCTAssertTrue(h.stdout.joined().contains(address))
        XCTAssertTrue(h.stderr.joined().contains("Use target NAME"))
    }

    @MainActor
    func testLibraryCancellationDoesNotWriteLaterFramesOrDisconnectCaller() async throws {
        let transport = TextStreamTransport()
        let client = TimeboxClient(model: .mini, transport: transport)
        try await client.connect(to: .mock)
        var task: Task<TimeboxTextStream, Error>!
        transport.afterWrite = { task.cancel() }
        task = Task { try await client.stream(text: "Hi") }
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(transport.packets.count, 1)
        XCTAssertTrue(transport.isConnected, "the library caller owns the persistent link")
        client.disconnect()
    }

    @MainActor
    func testLibraryPartialFailureNeverRestartsScroll() async throws {
        let transport = TextStreamTransport(); transport.failOnWrite = 2
        let client = TimeboxClient(model: .mini, transport: transport)
        try await client.connect(to: .mock)
        do { _ = try await client.stream(text: "Hi"); XCTFail("Expected failed second write") }
        catch { XCTAssertEqual(error as? TimeboxTransportError, .notConnected) }
        XCTAssertEqual(transport.packets.count, 1)
        client.disconnect()
    }
}

private final class TextStreamTransport: TimeboxTransport {
    var isConnected = false
    var onConnectionChange: ((Bool) -> Void)?
    var packets: [Data] = []
    var afterWrite: (() -> Void)?
    var failOnWrite: Int?
    func connect(to device: TimeboxDevice) async throws { isConnected = true }
    func disconnect() { isConnected = false }
    func write(_ data: Data) async throws {
        if failOnWrite == packets.count + 1 { throw TimeboxTransportError.notConnected }
        packets.append(data); afterWrite?()
    }
}
