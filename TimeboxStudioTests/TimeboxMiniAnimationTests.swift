import XCTest
@testable import TimeboxKit
@testable import TimeboxBluetooth

final class TimeboxMiniAnimationTests: XCTestCase {
    let fixture = "docs/validation/fixtures/mini-red-green-500ms.gif"
    private func animation(_ durations: [Int], model: TimeboxModel = .mini) throws -> TimeboxAnimation {
        try TimeboxAnimation(frames: durations.enumerated().map { index, duration in
            try TimeboxAnimationFrame(image: PixelFrame(fill: index % 2 == 0 ? .init(red:255,green:0,blue:0) : .init(red:0,green:255,blue:0), model: model), durationMilliseconds: duration)
        })
    }
    private func referencePackets() throws -> [Data] {
        try String(contentsOfFile: "docs/validation/fixtures/mini-animation-red-green.hex").split(separator:"\n").map {
            Data($0.split(separator:" ").map { UInt8($0,radix:16)! })
        }
    }

    func testPinnedMiniReferencePacketsAndModelSizedGIFMatchExactly() throws {
        let source = try GIFAnimationLoader.load(path: fixture, model: .mini)
        XCTAssertEqual(source.frames.map { $0.image.width }, [11,11])
        XCTAssertEqual(source.frames.map(\.durationMilliseconds), [500,500])
        let upload = try TimeboxAnimationEncoder.prepare(source, model: .mini)
        XCTAssertEqual(upload.packets, try referencePackets())
        XCTAssertEqual(upload.packets.map(\.count), [195,196])
        XCTAssertEqual(upload.frameDurationMilliseconds, 500)
        XCTAssertEqual(upload.effectiveMilliseconds, 1000)
        XCTAssertEqual(upload.paletteBits, 4)
        XCTAssertFalse(upload.adapted)
        // The default public path remains Evo, including its unescaped 0x49 stream.
        let evo = try GIFAnimationLoader.load(path: fixture)
        let evoUpload = try TimeboxAnimationEncoder.prepare(evo)
        XCTAssertEqual(evo.frames[0].image.width,16)
        XCTAssertEqual(evoUpload.packets.count,1)
        XCTAssertEqual(evoUpload.packets[0].count,94)
        XCTAssertFalse(evoUpload.adapted)
        XCTAssertThrowsError(try TimeboxAnimationEncoder.prepare(source))
        XCTAssertThrowsError(try TimeboxAnimation(frames: [source.frames[0],evo.frames[0]]))
    }

    func testLosslessRepeatedHoldsAndStaticSingleFrameAreReportedHonestly() throws {
        let unequal = try animation([500,1000])
        let upload = try TimeboxAnimationEncoder.prepare(unequal,model:.mini)
        XCTAssertEqual(upload.effectiveFrames,3)
        XCTAssertEqual(upload.frameDurationMilliseconds,500)
        XCTAssertEqual(upload.sourceMilliseconds,1500)
        XCTAssertEqual(upload.effectiveMilliseconds,1500)
        XCTAssertFalse(upload.adapted) // Native repeated holds preserve every source image and duration.
        let still = try animation([500])
        let staticUpload = try TimeboxAnimationEncoder.prepare(still,model:.mini)
        XCTAssertTrue(staticUpload.isStatic)
        XCTAssertEqual(staticUpload.effectiveMilliseconds,0) // No duration field exists in native static packets.
        XCTAssertNil(staticUpload.frameDurationMilliseconds)
        XCTAssertEqual(staticUpload.packets,[try TimeboxMiniEncoder.encode(.image(still.frames[0].image))])
    }

    func testConservativeTwelveFrameUniformDelayPolicyAndExplicitAdaptation() throws {
        XCTAssertEqual(try TimeboxAnimationEncoder.prepare(animation(Array(repeating:500,count:12)),model:.mini).effectiveFrames,12)
        let tooMany = try animation(Array(repeating:500,count:13))
        XCTAssertThrowsError(try TimeboxAnimationEncoder.prepare(tooMany,model:.mini))
        let adapted = try TimeboxAnimationEncoder.prepare(tooMany,model:.mini,adapt:true)
        XCTAssertLessThanOrEqual(adapted.effectiveFrames,12)
        XCTAssertEqual(adapted.effectiveMilliseconds,6500)
        XCTAssertTrue(adapted.adaptations.contains("temporal_sampling"))
        let fast = try animation([100,100])
        XCTAssertThrowsError(try TimeboxAnimationEncoder.prepare(fast,model:.mini))
        let slower = try TimeboxAnimationEncoder.prepare(fast,model:.mini,adapt:true)
        XCTAssertEqual(slower.effectiveMilliseconds,400)
        XCTAssertEqual(slower.frameDurationMilliseconds,200)
        XCTAssertTrue(slower.adaptations.contains("timing_rounding"))
        XCTAssertEqual(try TimeboxAnimationEncoder.prepare(animation([153000,153000]),model:.mini).effectiveFrames,12)
        XCTAssertThrowsError(try TimeboxAnimationEncoder.prepare(animation([153001,153001]),model:.mini,adapt:true))
    }

    func testCLIResolvesSavedModelBeforeConversionAndReportsNativeMetadata() throws {
        let h = CommandHarness()
        h.configuration = .init(defaultName:"mini",devices:["mini":.init(mac:"AA:BB:CC:DD:EE:01",model:.mini)])
        XCTAssertEqual(h.run(["animation",fixture,"--json"]),0,h.stderr.joined())
        XCTAssertEqual(h.transport.packets,try referencePackets())
        let result = try XCTUnwrap(JSONSerialization.jsonObject(with:Data(h.rawStdout.utf8)) as? [String:Any])
        let data = try XCTUnwrap(result["data"] as? [String:Any])
        XCTAssertEqual(data["palette_component_bits"] as? Int,4)
        XCTAssertEqual(data["frame_duration_ms"] as? Int,500)
        XCTAssertEqual(data["playback"] as? String,"animation")
        XCTAssertEqual(data["adapted"] as? Bool,false)
        let unknown = CommandHarness();unknown.detectedModels = []
        XCTAssertEqual(unknown.run(["animation","/nonexistent.gif","--address","AA:BB:CC:DD:EE:01","--json"]),1)
        XCTAssertTrue(unknown.rawStdout.contains("unknown_model"))
        XCTAssertTrue(unknown.transport.connections.isEmpty)
    }

    func testMiniPreflightAdaptationAndPartialFailureBeforeLaterFrames() {
        let invalid = CommandHarness()
        XCTAssertEqual(invalid.run(["animation","docs/validation/fixtures/animation-disposal.gif","--address","AA:BB:CC:DD:EE:01","--model","mini","--json"]),1)
        XCTAssertTrue(invalid.transport.connections.isEmpty)
        let adapted = CommandHarness()
        XCTAssertEqual(adapted.run(["animation","docs/validation/fixtures/animation-disposal.gif","--address","AA:BB:CC:DD:EE:01","--model","mini","--adapt","--json"]),0)
        XCTAssertTrue(adapted.rawStdout.contains("timing_rounding"))
        XCTAssertTrue(adapted.stderr.joined().contains("adapted"))
        let failed = CommandHarness();failed.transport.failOnWriteNumber = 2
        XCTAssertEqual(failed.run(["animation",fixture,"--address","AA:BB:CC:DD:EE:01","--model","mini"]),1)
        XCTAssertEqual(failed.transport.connections.count,1)
        XCTAssertEqual(failed.transport.packets.count,1)
        XCTAssertTrue(failed.stderr.joined().contains("partial"))
    }

    func testREPLUsesCurrentModelWhenSwitchingMiniToEvo() throws {
        let h = CommandHarness()
        h.configuration = .init(defaultName:"mini",devices:["mini":.init(mac:"AA:BB:CC:DD:EE:01",model:.mini),"evo":.init(mac:"AA:BB:CC:DD:EE:02",model:.evo)])
        h.input = ["animation " + fixture,"target evo","animation " + fixture,"quit"]
        XCTAssertEqual(h.run(["repl"]),0,h.stderr.joined())
        XCTAssertEqual(Array(h.transport.packets.prefix(2)),try referencePackets())
        XCTAssertEqual(h.transport.packets.count,3)
        XCTAssertEqual(h.transport.packets[2].count,94)
        XCTAssertEqual(h.transport.writeTargets,["AA:BB:CC:DD:EE:01","AA:BB:CC:DD:EE:01","AA:BB:CC:DD:EE:02"])
    }

    @MainActor
    func testLibraryPartialFailureStopsWithoutRetryOrLaterFrames() async throws {
        let transport = MiniAnimationTransport(); transport.failOnWrite = 2
        let client = TimeboxClient(model:.mini,transport:transport)
        try await client.connect(to:.mock)
        do { _ = try await client.send(animation:animation([500,500,500]));XCTFail("Expected second-frame failure") }
        catch { XCTAssertEqual(error as? TimeboxTransportError,.notConnected) }
        XCTAssertEqual(transport.packets.count,1)
        client.disconnect()
    }

    @MainActor
    func testLibraryUsesNativeMiniAnimationAndStillRejectsUnprovenScrollingText() async throws {
        let transport = MiniAnimationTransport()
        let client = TimeboxClient(model:.mini,transport:transport)
        try await client.connect(to:.mock)
        let upload = try await client.send(animation:animation([500,500]))
        XCTAssertEqual(transport.packets,try referencePackets())
        XCTAssertFalse(upload.adapted)
        do { _ = try await client.send(text:"Hello");XCTFail("Mini text requires a separate no-thinning design") }
        catch { guard case .unsupported = error as? TimeboxModelError else { return XCTFail("\(error)") } }
        XCTAssertEqual(transport.packets.count,2)
        let wrong = try animation([500,500],model:.evo)
        do { _ = try await client.send(animation:wrong);XCTFail("Expected model dimension rejection") }
        catch { XCTAssertTrue(error is TimeboxAnimationError) }
        XCTAssertEqual(transport.packets.count,2)
        client.disconnect()
    }
}

private final class MiniAnimationTransport: TimeboxTransport {
    var isConnected = false
    var onConnectionChange: ((Bool)->Void)?
    var packets:[Data] = []
    var failOnWrite: Int?
    func connect(to device:TimeboxDevice) async throws { isConnected=true }
    func disconnect() { isConnected=false }
    func write(_ data:Data) async throws {
        if failOnWrite == packets.count + 1 { throw TimeboxTransportError.notConnected }
        packets.append(data)
    }
}
