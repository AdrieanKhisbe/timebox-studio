import Foundation

extension TimeboxQuery where Response == [TimeboxAlarm] {
    /// Manufacturer's 0x42 query; ten records verified by the captured Evo reply.
    public static var alarms: Self {
        Self(request: Data([1, 3, 0, 0x42, 0x45, 0, 2]), responseCommand: 0x42,
             decode: TimeboxAlarmDecoder.decode)
    }
}
