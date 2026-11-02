import Foundation
import TimeboxBluetooth
import Yams

/// Shared one-result contract for discovery and ordinary one-shot commands.
struct CommandResult {
    let command: String
    let status: String
    var device: ResolvedDevice?
    var data: [String: Any]

    func formatted(_ format: OutputFormat) throws -> String {
        var result: [String: Any] = ["command": command, "status": status, "data": data]
        if let device {
            var value: [String: Any] = ["name": device.logicalName as Any? ?? NSNull(), "mac": device.device.address]
            if let resolution = device.modelResolution {
                value["model"] = resolution.model.rawValue; value["model_source"] = resolution.source.rawValue
            }
            if let resolution = device.protocolResolution {
                value["model"] = device.modelResolution?.model.rawValue as Any? ?? NSNull()
                value["protocol_family"] = resolution.family.rawValue
                value["protocol_source"] = resolution.source.rawValue
                value["transport"] = "classic"
                if let detection = resolution.detection {
                    value["protocol_detection_ms"] = detection.elapsedMilliseconds
                    value["protocol_query_ms"] = detection.queryMilliseconds
                }
            }
            result["device"] = value
        }
        switch format {
        case .json:
            return String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), as: UTF8.self) + "\n"
        case .yaml: return try Yams.dump(object: result, sortKeys: true)
        }
    }
}
