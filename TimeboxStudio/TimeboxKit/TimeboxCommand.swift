import Foundation

public enum TimeboxCommand: Equatable, Sendable {
    case startCountdown(TimeboxCountdownDuration)
    case stopCountdown
    case stopwatch(TimeboxStopwatchAction)
    case raw(Data)
    case synchronizeClock(TimeboxClockSnapshot)
    case display(TimeboxDisplay)
    case displayProfile(TimeboxDisplayProfile)
    /// Low-level verified index encoding. High-level callers must freshly gate
    /// device support through TimeboxDisplayWriter before channel/tab packets.
    case selectDesignTab(Int)
    case setBrightness(Int)
    /// PROTOCOL.md "Lightning channel" plain single color: fills the whole
    /// display with one color. A much more visible effect than brightness,
    /// useful for confirming the device actually reacts to packets.
    case lightningPlainColor(color: PixelRGB, brightnessPercent: Int)
    /// A static image at the selected model’s size (`SPP_SET_BOX_COLOR`).
    case image(PixelFrame)
    /// Update one slot, retaining the supplied live record's sound settings.
    case setAlarm(TimeboxAlarm, schedule: TimeboxAlarmSchedule, volume: Int? = nil)
    /// Disable one supplied live slot, preserving all other stored fields.
    case disableAlarm(TimeboxAlarm)
}
