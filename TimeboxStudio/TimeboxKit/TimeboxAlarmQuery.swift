import Foundation

extension TimeboxQuery where Response == [TimeboxAlarm] {
    /// Exact model-specific slot count; no empty or truncated list is accepted.
    public static var alarms: Self { alarms(model: .evo) }
    public static func alarms(model: TimeboxModel) -> Self {
        try! Self(payload: Data([0x42]), responseCommand: 0x42, model: model,
                  decode: { try TimeboxAlarmDecoder.decode($0, model: model) })
    }
}
