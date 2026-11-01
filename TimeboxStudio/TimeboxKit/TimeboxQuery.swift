import Foundation

/// A sourced request and decoder for its associated Evo NewMode response.
/// Command matching alone is safe only on a fresh, exclusively owned connection:
/// Evo replies have no transaction identifier. Do not use this for unsolicited
/// opcodes unless evidence distinguishes their notifications from query replies.
public struct TimeboxQuery<Response> {
    public let request: Data
    public let responseCommand: UInt8
    public let decode: (Data) throws -> Response

    init(request: Data, responseCommand: UInt8, decode: @escaping (Data) throws -> Response) {
        self.request = request
        self.responseCommand = responseCommand
        self.decode = decode
    }

    /// `payload` includes the documented request opcode, without a frame envelope.
    public init(payload: Data, responseCommand: UInt8,
                decode: @escaping (Data) throws -> Response) throws {
        guard !payload.isEmpty else { throw TimeboxResponseError.malformed("empty query payload") }
        self.request = try TimeboxPacketEncoder.encodePayload(payload)
        self.responseCommand = responseCommand
        self.decode = decode
    }
}
