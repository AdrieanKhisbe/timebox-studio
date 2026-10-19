import Foundation
import TimeboxKit

extension TimeboxCommandLine {
    func prepareAnimation(_ options: CommandOptions) throws -> TimeboxAnimationUpload {
        guard options.positionals.count == 1 else { throw CommandFailure("invalid_arguments", "animation requires one GIF path.") }
        guard let resize = TimeboxResizePolicy(rawValue: options.resize ?? "fit") else {
            throw CommandFailure("invalid_arguments", "--resize must be fit, fill or stretch.")
        }
        do {
            let animation = try GIFAnimationLoader.load(path: options.positionals[0], resize: resize)
            let upload = try TimeboxAnimationEncoder.prepare(animation, adapt: options.adapt)
            if upload.adapted {
                environment.errorOutput("Animation adapted: \(upload.sourceFrames) → \(upload.effectiveFrames) frames; \(upload.paletteBits)-bit RGB components; \(upload.sourceMilliseconds) → \(upload.effectiveMilliseconds) ms.")
            }
            return upload
        } catch { throw CommandFailure("invalid_media", error.localizedDescription) }
    }

    func animationData(_ upload: TimeboxAnimationUpload) -> [String: Any] {
        ["source_frames": upload.sourceFrames, "effective_frames": upload.effectiveFrames,
         "source_duration_ms": upload.sourceMilliseconds, "effective_duration_ms": upload.effectiveMilliseconds,
         "palette_component_bits": upload.paletteBits, "adapted": upload.adapted,
         "packets": upload.packets.count, "bytes": upload.packets.reduce(0) { $0 + $1.count }]
    }

    func sendAnimation(_ upload: TimeboxAnimationUpload, to target: ResolvedDevice, options: CommandOptions) throws {
        let transport = environment.makeTransport(options.mock)
        defer { transport.disconnect() }
        try connect(transport, to: target, channel: options.channel)
        transport.wait(milliseconds: 150)
        for packet in upload.packets {
            do { try transport.write(packet) }
            catch { throw CommandFailure("write_failed", "Animation upload failed and may be partial: " + error.localizedDescription) }
            transport.wait(milliseconds: 20)
        }
        transport.wait(milliseconds: options.holdMilliseconds)
        diagnostic(options.mock ? "Simulated animation upload." : "Sent animation upload.")
    }
}
