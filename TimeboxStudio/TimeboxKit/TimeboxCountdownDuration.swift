import Foundation

/// The official Bluetooth app's supported picker range: 00:01 through 59:59.
public struct TimeboxCountdownDuration: Equatable, Sendable {
    public let minutes: Int
    public let seconds: Int
    public var totalSeconds: Int { minutes * 60 + seconds }

    public init(minutes: Int, seconds: Int) throws {
        guard (0...59).contains(minutes), (0...59).contains(seconds), minutes != 0 || seconds != 0 else {
            throw TimeboxTimerError.invalidCountdown
        }
        self.minutes = minutes; self.seconds = seconds
    }

    /// Strict ASCII MM:SS. Hours, signs, whitespace, and implicit truncation are rejected.
    public init(_ text: String) throws {
        let bytes = Array(text.utf8)
        guard bytes.count == 5, bytes[2] == 58,
              [bytes[0], bytes[1], bytes[3], bytes[4]].allSatisfy({ (48...57).contains($0) }) else {
            throw TimeboxTimerError.invalidCountdown
        }
        try self.init(minutes: Int(bytes[0] - 48) * 10 + Int(bytes[1] - 48),
                      seconds: Int(bytes[3] - 48) * 10 + Int(bytes[4] - 48))
    }
}

public enum TimeboxTimerError: LocalizedError {
    case invalidCountdown
    public var errorDescription: String? { "Countdown requires MM:SS from 00:01 through 59:59 (the official app's supported range)." }
}
