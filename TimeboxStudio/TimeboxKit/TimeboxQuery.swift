import Foundation

/// A sourced request and decoder for its model-specific response framing.
/// Command matching alone is safe only on a fresh, exclusively owned connection:
/// These replies have no transaction identifier. Do not use this for unsolicited
/// opcodes unless evidence distinguishes their notifications from query replies.
public struct TimeboxQuery<Response> {
    public let model: TimeboxModel
    public let request: Data
    public let responseCommand: UInt8
    public let decode: (Data) throws -> Response
    /// Select an external subcommand before decoding. Other well-framed replies
    /// are ignored; this does not replace fresh-link ownership or strict framing.
    public let matchesResponseData: (Data) -> Bool

    init(request: Data, responseCommand: UInt8, model: TimeboxModel = .evo, decode: @escaping (Data) throws -> Response) {
        self.model = model
        self.request = request
        self.responseCommand = responseCommand
        self.decode = decode
        self.matchesResponseData = { _ in true }
    }

    /// `payload` includes the documented request opcode, without a frame envelope.
    public init(payload: Data, responseCommand: UInt8, model: TimeboxModel = .evo,
                matchingResponse: @escaping (Data) -> Bool = { _ in true },
                decode: @escaping (Data) throws -> Response) throws {
        guard !payload.isEmpty else { throw TimeboxResponseError.malformed("empty query payload") }
        self.model = model
        self.request = try model == .mini ? TimeboxMiniEncoder.frame(payload) : TimeboxPacketEncoder.encodePayload(payload)
        self.responseCommand = responseCommand
        self.decode = decode
        self.matchesResponseData = matchingResponse
    }
}

extension TimeboxQuery where Response == [TimeboxAlarm] {
    /// Exact model-specific slot count; no empty or truncated list is accepted.
    public static var alarms: Self { alarms(model: .evo) }
    public static func alarms(model: TimeboxModel) -> Self {
        try! Self(payload: Data([0x42]), responseCommand: 0x42, model: model,
                  decode: { try TimeboxAlarmDecoder.decode($0, model: model) })
    }
}
