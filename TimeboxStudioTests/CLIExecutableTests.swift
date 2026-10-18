import XCTest

/// Exercise the shipped entry point as well as the injected Bluetooth boundary.
final class CLIExecutableTests: XCTestCase {
    func testExecutableConfigLifecycleAndMockOutput() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let config = root.appendingPathComponent("config.yml")
        let original = "# keep\ndefault: desk\ndevices: {desk: {mac: 'AA:BB:CC:DD:EE:01', bluetooth_name: Timebox}}\n"
        try original.write(to: config, atomically: true, encoding: .utf8)
        let options = ["--config", config.path]
        let brightness = try invoke(["brightness", "50", "--device", "DESK", "--mock", "--json"] + options)
        XCTAssertEqual(brightness.exit, 0, brightness.stderr)
        let result = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(brightness.stdout.utf8)) as? [String: Any])
        XCTAssertEqual(result["status"] as? String, "simulated")
        XCTAssertTrue(brightness.stderr.contains("Connecting"))
        XCTAssertEqual(try invoke(["device", "rename", "desk", "Office desk"] + options).exit, 0)
        XCTAssertEqual(try invoke(["device", "select", "OFFICE DESK"] + options).exit, 0)
        let saved = try String(contentsOf: config, encoding: .utf8)
        XCTAssertTrue(saved.contains("# keep"))
        XCTAssertEqual(try invoke(["config", "show", "--yaml"] + options).stdout, saved)
        let repl = try invoke(["repl", "--name", "Office desk", "--mock"] + options,
                              input: "target current\nbrightness 50\nquit\n")
        XCTAssertEqual(repl.exit, 0, repl.stderr)
        XCTAssertTrue(repl.stdout.contains("Target: Office desk | AA:BB:CC:DD:EE:01 | connected"))
        XCTAssertEqual(try String(contentsOf: config, encoding: .utf8), saved)
        let failure = try invoke(["brightness", "101", "--json"] + options)
        XCTAssertEqual(failure.exit, 2)
        XCTAssertEqual((try JSONSerialization.jsonObject(with: Data(failure.stdout.utf8)) as? [String: Any])?["status"] as? String, "error")
        let diagnostic = try invoke(["scan-ble", "--json"])
        XCTAssertEqual(diagnostic.exit, 1)
        XCTAssertEqual((try JSONSerialization.jsonObject(with: Data(diagnostic.stdout.utf8)) as? [String: Any])?["status"] as? String, "error")
        let alarms = try invoke(["alarm", "list", "--mock", "--json"] + options)
        XCTAssertEqual(alarms.exit, 1)
        let alarmError = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(alarms.stdout.utf8)) as? [String: Any])
        XCTAssertEqual(alarmError["command"] as? String, "alarm list")
        XCTAssertEqual((alarmError["data"] as? [String: Any])?["code"] as? String, "unsupported")
    }

    private func invoke(_ arguments: [String], input: String = "") throws -> (exit: Int32, stdout: String, stderr: String) {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let process = Process()
        process.executableURL = repository.appendingPathComponent(".build/debug/timeboxctl")
        process.currentDirectoryURL = repository
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "TIMEBOX_ADDRESS")
        process.environment = environment
        let output = Pipe(), errors = Pipe(), stdin = Pipe()
        process.standardOutput = output; process.standardError = errors; process.standardInput = stdin
        try process.run()
        stdin.fileHandleForWriting.write(Data(input.utf8))
        try stdin.fileHandleForWriting.close()
        // These bounded, non-discovery mock commands produce less than a pipe buffer.
        process.waitUntilExit()
        return (process.terminationStatus,
                String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
                String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
    }
}
