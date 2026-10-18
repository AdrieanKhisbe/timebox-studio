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
            result["device"] = ["name": device.logicalName as Any? ?? NSNull(), "mac": device.device.address]
        }
        switch format {
        case .json:
            return String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), as: UTF8.self) + "\n"
        case .yaml: return try Yams.dump(object: result, sortKeys: true)
        }
    }
}
