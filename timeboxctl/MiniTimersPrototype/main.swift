// THROWAWAY: original 11x11 Mini feasibility experiment. Never infer an Evo profile.
import Foundation
import TimeboxKit
import TimeboxBluetooth

func hex(_ data: Data) -> String { data.map { String(format: "%02X", $0) }.joined(separator: " ") }
func problem(_ message: String) -> NSError { NSError(domain: "MiniPrototype", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }

let arguments = Array(CommandLine.arguments.dropFirst())
let sending = arguments.contains("--send")
func option(_ name: String) -> String? {
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}
let transport = IOBluetoothTimeboxTransport()
var alarmWasArmed = false
var originalAlarmSnapshot: [UInt8]?
var alarmDue: Date?
var selectedDevice: TimeboxDevice?
var selectedChannel: UInt8?

func decodeAlarmReply(_ wire: Data) throws -> [UInt8] {
    let bytes = Array(wire)
    var frames: [[UInt8]] = []
    var current: [UInt8]?; var escape = false
    for byte in bytes {
        if byte == 1 { current = []; escape = false; continue }
        guard current != nil else { continue } // Mini greeting is not a framed reply.
        if byte == 2 {
            guard !escape, let frame = current, frame.count >= 7 else { throw problem("Truncated Mini reply.") }
            guard Int(frame[0]) | (Int(frame[1]) << 8) == frame.count - 2 else { throw problem("Mini reply length mismatch.") }
            let checksum = frame.dropLast(2).reduce(0) { ($0 + Int($1)) & 65535 }
            guard checksum == Int(frame[frame.count-2]) | (Int(frame[frame.count-1]) << 8) else { throw problem("Mini reply checksum mismatch.") }
            frames.append(frame); current = nil; continue
        }
        if escape {
            guard (4...6).contains(byte) else { throw problem("Invalid Mini escape.") }
            current!.append(byte - 3); escape = false
        } else if byte == 3 { escape = true }
        else { current!.append(byte) }
    }
    guard let frame = frames.first(where: { Array($0[2...4]) == [4, 0x42, 0x55] }) else { throw problem("No successful complete42 reply; state remains unknown.") }
    let data = Array(frame.dropFirst(5).dropLast(2))
    guard data.count == 30 else { throw problem("Expected captured Mini layout of3×10bytes, got \(data.count).") }
    var ids = Set<UInt8>()
    for offset in stride(from: 0, to: 30, by: 10) {
        guard data[offset] <= 2, ids.insert(data[offset]).inserted, data[offset+1] <= 1,
              data[offset+2] < 24, data[offset+3] < 60, data[offset+9] <= 100 else { throw problem("Malformed Mini alarm record.") }
    }
    return data
}

@discardableResult func readAlarmSnapshot() throws -> [UInt8] {
    guard sending, let device = selectedDevice else {
        print("DRY RUN read Mini3-slot snapshot: \(hex(try TimeboxMiniEncoder.frame(Data([0x42]))))")
        return [0,0,0,0,0,0,1,0,0,50, 1,0,0,0,0,0,1,0,0,50, 2,0,0,0,0,0,1,0,0,50]
    }
    transport.disconnect(); transport.waitPumpingRunLoop(milliseconds: 500)
    try transport.connectPumpingRunLoop(to: device, channelID: selectedChannel)
    transport.onData = nil
    try transport.beginQuery()
    var raw = Data()
    transport.onData = { raw.append($0); print("RX alarm raw: \(hex($0))") }
    do {
        let request = try TimeboxMiniEncoder.frame(Data([0x42]))
        print("TX read Mini3-slot snapshot: \(hex(request))")
        try transport.writeQuery(request)
        transport.waitForQuery(milliseconds: 5000)
    } catch {
        transport.onData = nil; transport.disconnect(); transport.endQuery(); throw error
    }
    transport.onData = nil; transport.disconnect(); transport.endQuery()
    let data = try decodeAlarmReply(raw)
    print("ALARM SNAPSHOT30: \(hex(Data(data)))")
    transport.waitPumpingRunLoop(milliseconds: 500)
    try transport.connectPumpingRunLoop(to: device, channelID: selectedChannel)
    transport.onData = { print("RX raw: \(hex($0))") }
    print("RECONNECTED after fresh alarm query.")
    return data
}

func restoreAlarm() throws {
    guard let baseline = originalAlarmSnapshot else { throw problem("No original snapshot to restore.") }
    let offset = stride(from: 0, to: 30, by: 10).first { baseline[$0] == 2 }!
    try transmit([0x43] + Array(baseline[offset..<offset+10]), label: "restore exact original slot2")
    let actual = try readAlarmSnapshot()
    guard actual == baseline else { throw problem("Restoration readback differs; clear experimental alarm in app.") }
    alarmWasArmed = false; alarmDue = nil; originalAlarmSnapshot = nil
    print(sending ? "RESTORED: all3records match original snapshot exactly." : "DRY RUN: original snapshot restoration planned; no hardware verification claimed.")
}

func armAlarm(hour: UInt8, minute: UInt8) throws {
    guard !alarmWasArmed else { throw problem("Restore current experiment with alarm off first.") }
    let snapshot = try readAlarmSnapshot()
    let offset = stride(from: 0, to: 30, by: 10).first { snapshot[$0] == 2 }!
    guard snapshot[offset+1] == 0 else { throw problem("Slot2 is enabled; refusing to replace it.") }
    var expected = snapshot
    expected[offset+1] = 1; expected[offset+2] = hour; expected[offset+3] = minute; expected[offset+4] = 0
    originalAlarmSnapshot = snapshot; alarmWasArmed = true
    try transmit([0x43] + Array(expected[offset..<offset+10]), label: "Mini full-record slot2 alarm")
    if sending {
        let actual = try readAlarmSnapshot()
        guard actual == expected else { throw problem("Alarm readback mismatch; use alarm off to restore original snapshot.") }
        print("VERIFIED: slot2 setting matches, both other records unchanged. Physical trigger still unverified.")
    } else { print("DRY RUN: after write, require fresh readback equal to expected snapshot; no verification claimed.") }
}

func transmit(_ payload: [UInt8], label: String) throws {
    let packet = try TimeboxMiniEncoder.frame(Data(payload))
    print("\(sending ? "TX" : "DRY RUN") \(label): \(hex(packet))")
    if sending {
        try transport.writePumpingRunLoop(packet)
        transport.waitPumpingRunLoop(milliseconds: 250)
    }
}

let digits = [
    ["111","101","101","101","111"], ["010","110","010","010","111"],
    ["111","001","111","100","111"], ["111","001","111","001","111"],
    ["101","101","111","001","001"], ["111","100","111","001","111"],
    ["111","100","111","101","111"], ["111","001","001","001","001"],
    ["111","101","111","101","111"], ["111","101","111","001","111"]
]
func countdownFrame(_ remaining: Int) throws -> PixelFrame {
    var pixels = [PixelRGB](repeating: .init(red: 0, green: 0, blue: 0), count: 121)
    let color = remaining == 0 ? PixelRGB(red: 0, green: 255, blue: 0) : PixelRGB(red: 255, green: 255, blue: 255)
    for (place, char) in String(format: "%03d", remaining).enumerated() {
        let glyph = digits[Int(String(char))!]
        for (row, line) in glyph.enumerated() {
            for (column, bit) in line.enumerated() where bit == "1" {
                pixels[(row + 3) * 11 + place * 4 + column] = color
            }
        }
    }
    return try PixelFrame(pixels: pixels, model: .mini)
}

func hostCountdown(_ seconds: Int) throws {
    guard (1...180).contains(seconds) else { throw problem("Prototype countdown accepts 1...180 seconds.") }
    print("HOST-DRIVEN countdown: \(seconds) seconds; Mini receives images, not a native timer command. No device completion sound is requested.")
    if !sending {
        for remaining in [seconds, 0] {
            print("DRY RUN image \(remaining): \(hex(try TimeboxPacketEncoder.encode(.image(countdownFrame(remaining)), model: .mini)))")
        }
        return
    }
    let start = DispatchTime.now().uptimeNanoseconds
    for remaining in stride(from: seconds, through: 0, by: -1) {
        let deadline = start + UInt64(seconds - remaining) * 1_000_000_000
        while DispatchTime.now().uptimeNanoseconds < deadline {
            transport.waitPumpingRunLoop(milliseconds: 10)
        }
        let packet = try TimeboxPacketEncoder.encode(.image(countdownFrame(remaining)), model: .mini)
        try transport.writePumpingRunLoop(packet)
        print("HOST COUNTDOWN remaining=\(remaining), image_bytes=\(packet.count)")
    }
    transport.waitPumpingRunLoop(milliseconds: 250)
    print("HOST COUNTDOWN complete; green 000 remains visible while connected.")
}

func handle(_ line: String) throws -> Bool {
    let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
    guard let command = parts.first else { return true }
    switch command {
    case "quit", "exit": return false
    case "help":
        print("clock | stopwatch start|stop|reset (native Mini) | countdown SECONDS (host-driven) | alarm-read | alarm-next | alarm-in2 HH:MM (slot2 about2min ahead) | alarm HH:MM | alarm off (restore snapshot) | alarm-watch (wait then restore) | wait SECONDS | quit")
    case "clock":
        try transmit([0x45, 0, 1], label: "Mini 24-hour clock")
    case "stopwatch":
        guard parts.count == 2, let action = ["start": UInt8(1), "stop": UInt8(0), "reset": UInt8(2)][parts[1]] ?? UInt8(parts[1]), action <= 2 else { throw problem("Use stopwatch start, stop or reset (numeric0..2 also accepted).") }
        try transmit([0x45, 6, action], label: "Mini native stopwatch action \(action)")
    case "countdown":
        guard parts.count == 2, let seconds = Int(parts[1]) else { throw problem("Use countdown SECONDS.") }
        try hostCountdown(seconds)
    case "alarm-read": try readAlarmSnapshot()
    case "alarm-next":
        let due = Date().addingTimeInterval(120)
        let calendar = Calendar.current
        let h = calendar.component(.hour, from: due), m = calendar.component(.minute, from: due)
        print(String(format: "HOST target %02d:%02d local; Mini clock must already match. No clock sync sent.", h, m))
        try armAlarm(hour: UInt8(h), minute: UInt8(m))
        alarmDue = calendar.date(bySettingHour: h, minute: m, second: 0, of: due)
        print("ALARM ARMED; run alarm-watch for automatic wait/restoration, or alarm off now.")
    case "alarm-in2":
        guard parts.count == 2 else { throw problem("Use alarm-in2 HH:MM with the displayed Mini time.") }
        let time = parts[1].split(separator: ":")
        guard time.count == 2, let h = Int(time[0]), let m = Int(time[1]), (0...23).contains(h), (0...59).contains(m) else { throw problem("Invalid Mini time.") }
        let target = (h * 60 + m + 2) % 1440
        print(String(format: "MINI-CLOCK target %02d:%02d, based on user-reported display %@. Host clock is not copied to device.", target / 60, target % 60, parts[1]))
        try armAlarm(hour: UInt8(target / 60), minute: UInt8(target % 60))
        alarmDue = Date().addingTimeInterval(120)
        print("ALARM ARMED; alarm-watch will wait up to140seconds and restore all original records.")
    case "alarm-watch":
        guard let due = alarmDue else { throw problem("Use alarm-next first.") }
        let end = due.addingTimeInterval(20)
        guard end.timeIntervalSinceNow < 180 else { throw problem("Unexpected alarm deadline.") }
        if sending {
            while Date() < end {
                print("ALARM WATCH seconds-to-target=\(Int(due.timeIntervalSinceNow))")
                transport.waitPumpingRunLoop(milliseconds: 5000)
            }
        }
        try restoreAlarm()
    case "alarm":
        guard parts.count == 2 else { throw problem("Use alarm HH:MM or alarm off.") }
        if parts[1] == "off" { try restoreAlarm() }
        else {
            let time = parts[1].split(separator: ":")
            guard time.count == 2, let h = UInt8(time[0]), let m = UInt8(time[1]), h < 24, m < 60 else { throw problem("Invalid HH:MM.") }
            try armAlarm(hour: h, minute: m)
        }
    case "wait":
        guard parts.count == 2, let seconds = Int(parts[1]), (0...180).contains(seconds) else { throw problem("Use wait 0...180.") }
        if sending { transport.waitPumpingRunLoop(milliseconds: seconds * 1000) }
    default: throw problem("Unknown prototype command. Use help.")
    }
    return true
}

do {
    setbuf(stdout, nil)
    print("THROWAWAY Mini timers/alarm experiment. Dry run is default. No production capability claim.")
    if sending {
        guard let address = option("--address") else { throw problem("--send requires explicit --address. No device is selected automatically.") }
        let channel: UInt8?
        if let value = option("--channel"), value != "auto" {
            guard let number = UInt8(value), number > 0 else { throw problem("Invalid channel.") }
            channel = number
        } else { channel = nil }
        let device = TimeboxDevice(name: "explicit Mini", address: address, isPaired: true, isConnected: false, source: .bluetooth)
        selectedDevice = device; selectedChannel = channel
        try transport.connectPumpingRunLoop(to: device, channelID: channel)
        transport.onData = { print("RX (raw, not a verified readback): \(hex($0))") }
        transport.waitPumpingRunLoop(milliseconds: 150)
        print("CONNECTED channel=\(transport.lastRFCOMMChannelID.map(String.init) ?? "unknown"). No settings sent at startup.")
    }
    defer {
        if sending && alarmWasArmed {
            print("CLEANUP: attempting to disable the single experimental alarm.")
            do { try restoreAlarm() }
            catch { print("WARNING: disable failed; clear the alarm in the official app: \(error)") }
        }
        transport.disconnect()
    }
    if arguments.first == "plan" {
        for line in ["stopwatch 2", "stopwatch 1", "stopwatch 0", "alarm 07:30", "alarm off", "countdown 30"] { _ = try handle(line) }
    } else {
        _ = try handle("help")
        while true {
            print("mini-prototype> ", terminator: "")
            guard let line = readLine() else { break }
            do { if try !handle(line) { break } }
            catch { print("ERROR \(error.localizedDescription)") }
        }
    }
} catch {
    fputs("ERROR \(error.localizedDescription)\n", stderr)
    exit(1)
}
