import Foundation

public enum TimeboxCommand: Equatable, Sendable {
    case raw(Data)
    case synchronizeClock(TimeboxClockSnapshot)
    case setBrightness(Int)
    /// PROTOCOL.md "Lightning channel" plain single color: fills the whole
    /// display with one color. A much more visible effect than brightness,
    /// useful for confirming the device actually reacts to packets.
    case lightningPlainColor(color: PixelRGB, brightnessPercent: Int)
    /// A 16x16 static image (`SPP_SET_BOX_COLOR`): the "show whatever we want" command.
    case image(PixelFrame)
    /// Update one slot, retaining the supplied live record's sound settings.
    case setAlarm(TimeboxAlarm, schedule: TimeboxAlarmSchedule, volume: Int? = nil)
    /// Disable one supplied live slot, preserving all other stored fields.
    case disableAlarm(TimeboxAlarm)
}
