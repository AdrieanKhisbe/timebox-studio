import Foundation

/// Original Mini conservative, source-backed policy; not measured firmware capacity.
public enum TimeboxMiniAnimationEncoder {
    public static let maximumFrames = 12
    public static let minimumFrameMilliseconds = 200
    public static let maximumFrameMilliseconds = 25_500

    static func prepare(_ animation: TimeboxAnimation, adapt: Bool) throws -> TimeboxAnimationUpload {
        if animation.frames.count == 1 {
            let packet = try TimeboxMiniEncoder.encode(.image(animation.frames[0].image))
            return TimeboxAnimationUpload(packets: [packet], sourceFrames: 1, effectiveFrames: 1,
                sourceMilliseconds: animation.totalMilliseconds, effectiveMilliseconds: 0, paletteBits: 4,
                model: .mini, isStatic: true, frameDurationMilliseconds: nil, adaptations: [])
        }
        let source = animation.frames
        var selected: [PixelFrame] = []
        var tick = 0
        var changes: [String] = []
        // Exact representable timing can require duplicate native frames. Prefer
        // the longest common tick so lossless holds consume as few slots as possible.
        if source.count <= maximumFrames {
            for candidate in stride(from: maximumFrameMilliseconds, through: minimumFrameMilliseconds, by: -100) {
                guard source.allSatisfy({ $0.durationMilliseconds % candidate == 0 }) else { continue }
                let count = source.reduce(0) { $0 + $1.durationMilliseconds / candidate }
                guard count <= maximumFrames else { continue }
                tick = candidate
                for frame in source { selected += Array(repeating: frame.image, count: frame.durationMilliseconds / tick) }
                break
            }
        }
        if selected.isEmpty {
            guard adapt else {
                throw TimeboxAnimationError.invalid("Mini animation requires at most 12 native frames with a common 200...25500ms delay in 100ms steps. Use --adapt to permit temporal sampling/timing changes.")
            }
            guard animation.totalMilliseconds <= maximumFrames * maximumFrameMilliseconds else {
                throw TimeboxAnimationError.invalid("Mini animation duration exceeds the conservative 12 × 25500ms envelope; shorten it.")
            }
            // Minimize duration error, then retain the most native frames. Sample
            // the original timeline uniformly; report every lossy semantic change.
            var best: (error: Int, count: Int, tick: Int)?
            for candidate in stride(from: minimumFrameMilliseconds, through: maximumFrameMilliseconds, by: 100) {
                let count = max(2, min(maximumFrames, Int((Double(animation.totalMilliseconds) / Double(candidate)).rounded())))
                let error = abs(count * candidate - animation.totalMilliseconds)
                if best == nil || error < best!.error || (error == best!.error && count > best!.count) {
                    best = (error, count, candidate)
                }
            }
            guard let best else { throw TimeboxAnimationError.invalid("Cannot fit Mini animation timing.") }
            tick = best.tick
            var index = 0, end = source[0].durationMilliseconds
            for slot in 0..<best.count {
                let instant = slot * animation.totalMilliseconds / best.count
                while instant >= end, index + 1 < source.count { index += 1; end += source[index].durationMilliseconds }
                selected.append(source[index].image)
            }
            changes = ["temporal_sampling"]
            if best.error != 0 { changes.append("timing_rounding") }
        }
        var packets: [Data] = []
        for (index, image) in selected.enumerated() {
            // Mini reference sends one entire frame per 0x49 command: no Evo
            // total-stream size field, palette header, or 200-byte chunk splitting.
            var payload = Data([0x49, 0, 0x0A, 0x0A, 4, UInt8(index), UInt8(tick / 100)])
            payload.append(try TimeboxMiniEncoder.imagePayload(image).dropFirst(5))
            packets.append(try TimeboxMiniEncoder.frame(payload))
        }
        return TimeboxAnimationUpload(packets: packets, sourceFrames: source.count,
            effectiveFrames: selected.count, sourceMilliseconds: animation.totalMilliseconds,
            effectiveMilliseconds: selected.count * tick, paletteBits: 4, model: .mini,
            isStatic: false, frameDurationMilliseconds: tick, adaptations: changes)
    }
}
