/// Bluetooth tools mode zero. Stop pauses; reset is a distinct command.
public enum TimeboxStopwatchAction: UInt8, Equatable, Sendable {
    case stop = 0
    case start = 1
    case reset = 2
}
