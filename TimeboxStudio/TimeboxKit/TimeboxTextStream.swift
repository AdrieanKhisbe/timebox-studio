import Foundation

/// One complete host-driven scroll, including blank entry/exit viewports.
/// Prepare every static-image packet before opening a transport. This is not
/// a native looping animation and never thins frames to fit a device buffer.
public struct TimeboxTextStream: Sendable {
    public let packets: [Data]
    public let fontName: String
    public let model: TimeboxModel
    public let rasterWidth: Int
    public let frameMilliseconds = 100
    public var durationMilliseconds: Int { packets.count * frameMilliseconds }

    public init(_ text: String, model: TimeboxModel = .evo) throws {
        let rendered = try TimeboxTextRenderer.render(text, model: model)
        self.model = model
        fontName = rendered.fontName
        rasterWidth = rendered.rasterWidth
        packets = try rendered.animation.frames.map { try TimeboxPacketEncoder.encode(.image($0.image), model: model) }
    }
}
