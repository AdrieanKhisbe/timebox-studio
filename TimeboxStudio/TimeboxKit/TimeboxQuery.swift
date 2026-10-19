import Foundation

/// A sourced request and decoder for its associated Evo NewMode response.
/// Command matching alone is safe only on a fresh, exclusively owned connection:
/// Evo replies have no transaction identifier. Do not use this for unsolicited
/// opcodes unless evidence distinguishes their notifications from query replies.
public struct TimeboxQuery<Response> {
    public let request: Data
    public let responseCommand: UInt8
    public let decode: (Data) throws -> Response
    /// Select an external subcommand before decoding. Other well-framed replies
    /// are ignored; this does not replace fresh-link ownership or strict framing.
    public let matchesResponseData: (Data) -> Bool

    init(request: Data, responseCommand: UInt8, decode: @escaping (Data) throws -> Response) {
        self.request = request
        self.responseCommand = responseCommand
        self.decode = decode
        self.matchesResponseData = { _ in true }
    }

    /// `payload` includes the documented request opcode, without a frame envelope.
    public init(payload: Data, responseCommand: UInt8,
                matchingResponse: @escaping (Data) -> Bool = { _ in true },
                decode: @escaping (Data) throws -> Response) throws {
        guard !payload.isEmpty else { throw TimeboxResponseError.malformed("empty query payload") }
        self.request = try TimeboxPacketEncoder.encodePayload(payload)
        self.responseCommand = responseCommand
        self.decode = decode
        self.matchesResponseData = matchingResponse
    }
}

extension TimeboxQuery where Response == [TimeboxAlarm] {
    /// Manufacturer's 0x42 query; ten records verified by the captured Evo reply.
    public static var alarms: Self {
        Self(request: Data([1, 3, 0, 0x42, 0x45, 0, 2]), responseCommand: 0x42,
             decode: TimeboxAlarmDecoder.decode)
    }
}
