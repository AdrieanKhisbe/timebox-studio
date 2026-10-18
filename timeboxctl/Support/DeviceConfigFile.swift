import Foundation
import TimeboxBluetooth
import Yams

public struct DeviceConfigDocument {
    public let text: String
    public let configuration: DeviceConfiguration
    public let exists: Bool

    init(text: String, exists: Bool) throws {
        self.text = text; self.exists = exists
        do {
            guard let root = try Yams.compose(yaml: text) else { configuration = .init(); return }
            let fields = try Self.fields(root)
            var devices: [String: ConfiguredDevice] = [:]
            var addresses = Set<String>()
            if let node = fields["devices"] {
                for (name, value) in try Self.fields(node) {
                    guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                          !devices.keys.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else {
                        throw CommandFailure("invalid_config", "Duplicate or empty logical device name: \(name).")
                    }
                    let entry = try Self.fields(value)
                    guard let macNode = entry["mac"], let mac = Self.string(macNode) else {
                        throw CommandFailure("invalid_config", "Device '\(name)' needs a string mac field.")
                    }
                    let canonical = try DeviceResolver.canonicalMAC(mac)
                    guard addresses.insert(canonical).inserted else { throw CommandFailure("invalid_config", "Duplicate device address: \(canonical).") }
                    var bluetoothName: String?
                    if let value = entry["bluetooth_name"] {
                        guard let name = Self.string(value) else { throw CommandFailure("invalid_config", "bluetooth_name must be a string.") }
                        bluetoothName = name
                    }
                    devices[name] = ConfiguredDevice(mac: canonical, bluetoothName: bluetoothName)
                }
            }
            var defaultName: String?
            if let value = fields["default"], value.tag.description != "tag:yaml.org,2002:null" {
                guard let name = Self.string(value), devices[name] != nil else {
                    throw CommandFailure("invalid_config", "The default must name an existing configured device exactly.")
                }
                defaultName = name
            }
            configuration = DeviceConfiguration(defaultName: defaultName, devices: devices)
        } catch {
            throw CommandFailure("invalid_config", "Invalid config file: \(error.localizedDescription)")
        }
    }

    static func string(_ node: Node) -> String? {
        guard node.tag.description == "tag:yaml.org,2002:str" else { return nil }
        return node.scalar?.string
    }

    static func fields(_ node: Node) throws -> [String: Node] {
        guard let mapping = node.mapping else { throw CommandFailure("invalid_config", "Expected a YAML mapping.") }
        var fields: [String: Node] = [:]
        for pair in mapping {
            guard let key = string(pair.key), fields[key] == nil else {
                throw CommandFailure("invalid_config", "Mapping keys must be unique strings.")
            }
            fields[key] = pair.value
        }
        return fields
    }
}

public struct DeviceConfigFile {
    public let url: URL
    public init(url: URL) { self.url = url }
    public init(path: String? = nil) {
        url = path.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/timebox-studio/config.yml")
    }

    public func read() throws -> DeviceConfigDocument {
        do {
            let bytes = try Data(contentsOf: url)
            guard let text = String(data: bytes, encoding: .utf8) else { throw CommandFailure("invalid_config", "Config must be UTF-8.") }
            return try DeviceConfigDocument(text: text, exists: true)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return try DeviceConfigDocument(text: "", exists: false)
        } catch let error as CommandFailure { throw error }
        catch { throw CommandFailure("invalid_config", "Cannot read \(url.path): \(error.localizedDescription)") }
    }

    @discardableResult
    public func saveDiscovered(_ discovered: [TimeboxDevice]) throws -> DeviceConfigDocument {
        let original = try read()
        var configuration = original.configuration
        var editor = YAMLSourceEditor(text: original.text)
        var seen = Set<String>()
        for device in discovered.filter(\.isTimeboxCandidate).sorted(by: { $0.address.lowercased() < $1.address.lowercased() }) {
            let mac = try DeviceResolver.canonicalMAC(device.address)
            guard seen.insert(mac).inserted else { continue }
            let existing = configuration.devices.keys.first { configuration.devices[$0]?.mac == mac }
            var name = existing ?? device.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty { name = "Timebox" }
            if existing == nil {
                let base = name
                let suffix = mac.replacingOccurrences(of: ":", with: "").suffix(6).lowercased()
                if configuration.name(matching: name) != nil { name = "\(base)-\(suffix)" }
                var count = 2
                while configuration.name(matching: name) != nil { name = "\(base)-\(suffix)-\(count)"; count += 1 }
                try editor.set(["devices", name], value: .mapping([
                    "mac": .string(mac), "bluetooth_name": .string(device.name)
                ]))
            } else {
                try editor.set(["devices", name, "mac"], value: .string(mac))
                try editor.set(["devices", name, "bluetooth_name"], value: .string(device.name))
            }
            configuration.devices[name] = .init(mac: mac, bluetoothName: device.name)
        }
        if configuration.defaultName == nil, let name = configuration.devices.keys.sorted().first {
            try editor.set(["default"], value: .string(name))
        }
        if editor.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try editor.set(["devices"], value: .mapping([:]))
        }
        return try write(editor.text, replacing: original)
    }

    func write(_ text: String, replacing original: DeviceConfigDocument) throws -> DeviceConfigDocument {
        let result = try DeviceConfigDocument(text: text, exists: true)
        let current = try read()
        guard current.text == original.text, current.exists == original.exists else {
            throw CommandFailure("invalid_config", "Config changed while editing; retry the command.")
        }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url, options: .atomic)
        } catch { throw CommandFailure("invalid_config", "Cannot save config file: \(error.localizedDescription)") }
        return result
    }

    @discardableResult
    public func select(_ name: String) throws -> DeviceConfigDocument {
        let original = try read()
        guard let key = original.configuration.name(matching: name) else {
            throw CommandFailure("device_not_found", "Unknown logical device: \(name). Run timeboxctl list --save first.")
        }
        var editor = YAMLSourceEditor(text: original.text)
        try editor.set(["default"], value: .string(key))
        return try write(editor.text, replacing: original)
    }

    @discardableResult
    public func rename(_ old: String, to new: String) throws -> DeviceConfigDocument {
        let original = try read()
        guard let key = original.configuration.name(matching: old) else {
            throw CommandFailure("device_not_found", "Unknown logical device: \(old).")
        }
        guard !new.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CommandFailure("invalid_arguments", "The new logical name must not be empty.")
        }
        if let collision = original.configuration.name(matching: new), collision != key {
            throw CommandFailure("invalid_arguments", "A device named '\(new)' already exists.")
        }
        var editor = YAMLSourceEditor(text: original.text)
        try editor.renameKey(in: ["devices"], from: key, to: new)
        if original.configuration.defaultName == key { try editor.set(["default"], value: .string(new)) }
        return try write(editor.text, replacing: original)
    }
}

/// Yams validates/locates nodes. Only edited tokens are replaced; the original
/// source retains comments, unknown fields, key order and untouched formatting.
struct YAMLSourceEditor {
    indirect enum Value {
        case string(String)
        case mapping([String: Value])
        static func key(_ name: String) -> String {
            // Validate plain spelling with the same YAML resolver used on read.
            // Values such as true/null and punctuation names still need quoting.
            if !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
               let root = try? Yams.compose(yaml: "{\(name): null}"),
               let mapping = root.mapping, mapping.count == 1,
               let pair = mapping.first, DeviceConfigDocument.string(pair.key) == name,
               pair.key.scalar?.style == .plain {
                return name
            }
            return Value.string(name).flow
        }
        var flow: String {
            switch self {
            case .string(let value): return String(data: try! JSONEncoder().encode(value), encoding: .utf8)!
            case .mapping(let values): return "{" + values.keys.sorted().map { Value.key($0) + ": " + values[$0]!.flow }.joined(separator: ", ") + "}"
            }
        }
        func entry(_ key: String, indent: Int, newline: String) -> String {
            if case .mapping(let entries) = self, !entries.isEmpty {
                return Value.key(key) + ":" + newline + entries.keys.sorted().map {
                    String(repeating: " ", count: indent + 2) + entries[$0]!.entry($0, indent: indent + 2, newline: newline)
                }.joined(separator: newline)
            }
            return Value.key(key) + ": " + flow
        }
    }
    var text: String
    private var scalars: [UnicodeScalar] { Array(text.unicodeScalars) }
    private var newline: String { text.contains("\r\n") ? "\r\n" : "\n" }

    mutating func set(_ path: [String], value: Value) throws {
        guard let root = try Yams.compose(yaml: text) else {
            var nested = value
            for key in path.dropFirst().reversed() { nested = .mapping([key: nested]) }
            if !text.isEmpty && !text.hasSuffix("\n") { text += newline }
            text += nested.entry(path[0], indent: 0, newline: newline) + newline
            return
        }
        try set(in: root, path: path, value: value)
    }

    private mutating func set(in parent: Node, path: [String], value: Value) throws {
        guard let mapping = parent.mapping, let key = path.first else { throw unsafe() }
        let pair = mapping.first { $0.key.scalar?.string == key }
        if let pair {
            if path.count > 1 { try set(in: pair.value, path: Array(path.dropFirst()), value: value); return }
            guard case .string = value else { throw unsafe() }
            replace(try scalarRange(pair.value, flow: isFlow(parent)), with: value.flow)
            return
        }
        var nested = value
        for component in path.dropFirst().reversed() { nested = .mapping([component: nested]) }
        if isFlow(parent) {
            guard let mark = parent.mark else { throw unsafe() }
            let start = offset(mark)
            let close = try closingBrace(from: start)
            replace(close..<close, with: (mapping.isEmpty ? "" : ", ") + Value.key(key) + ": " + nested.flow)
        } else if let first = mapping.first, let mark = first.key.mark {
            let position = offset(mark), indent = mark.column - 1
            replace(position..<position, with: nested.entry(key, indent: indent, newline: newline) + newline + String(repeating: " ", count: indent))
        } else { throw unsafe() }
    }

    private func isFlow(_ node: Node) -> Bool {
        guard let mark = node.mark else { return false }
        let index = offset(mark)
        return index < scalars.count && scalars[index] == "{"
    }

    mutating func renameKey(in path: [String], from old: String, to new: String) throws {
        guard var node = try Yams.compose(yaml: text) else { throw unsafe() }
        for component in path {
            guard let next = node.mapping?.first(where: { $0.key.scalar?.string == component })?.value else { throw unsafe() }
            node = next
        }
        guard let pair = node.mapping?.first(where: { $0.key.scalar?.string == old }) else { throw unsafe() }
        replace(try scalarRange(pair.key, flow: isFlow(node), isKey: true), with: Value.key(new))
    }

    private func offset(_ mark: Mark) -> Int {
        let bytes = scalars
        var position = 0, line = 1
        while position < bytes.count && line < mark.line {
            if bytes[position] == "\n" { line += 1 }
            position += 1
        }
        return position + mark.column - 1
    }

    private func scalarRange(_ node: Node, flow: Bool = false, isKey: Bool = false) throws -> Range<Int> {
        guard let scalar = node.scalar, let mark = scalar.mark, scalar.anchor == nil,
              scalar.style != .literal, scalar.style != .folded else { throw unsafe() }
        let bytes = scalars, start = offset(mark)
        guard start < bytes.count else { return start..<start }
        let quote = bytes[start]
        var end = start
        if quote == "\"" || quote == "'" {
            end += 1
            while end < bytes.count {
                if quote == "\"", bytes[end] == "\\" { end += 2; continue }
                if bytes[end] == quote {
                    if quote == "'", end + 1 < bytes.count, bytes[end + 1] == quote { end += 2; continue }
                    return start..<(end + 1)
                }
                end += 1
            }
            throw unsafe()
        }
        while end < bytes.count {
            let byte = bytes[end]
            if byte == "\n" || byte == "\r" || (flow && (byte == "," || byte == "}" || byte == "]")) { break }
            if isKey, byte == ":", end + 1 == bytes.count || CharacterSet.whitespacesAndNewlines.contains(bytes[end + 1]) || ["{", "[", "}", "]", ","].contains(bytes[end + 1]) { break }
            if byte == "#", end == start || CharacterSet.whitespaces.contains(bytes[end - 1]) { break }
            end += 1
        }
        while end > start && CharacterSet.whitespaces.contains(bytes[end - 1]) { end -= 1 }
        guard String(String.UnicodeScalarView(bytes[start..<end])) == scalar.string else { throw unsafe() }
        return start..<end
    }

    private func closingBrace(from start: Int) throws -> Int {
        let bytes = scalars
        var depth = 0, quote: UnicodeScalar?, escaped = false, comment = false
        for i in start..<bytes.count {
            let byte = bytes[i]
            if comment { if byte == "\n" { comment = false }; continue }
            if let current = quote {
                if escaped { escaped = false; continue }
                if current == "\"", byte == "\\" { escaped = true; continue }
                if byte == current { quote = nil }
                continue
            }
            if byte == "\"" || byte == "'" { quote = byte; continue }
            if byte == "#" { comment = true; continue }
            if byte == "{" { depth += 1 }
            if byte == "}" { depth -= 1; if depth == 0 { return i } }
        }
        throw unsafe()
    }

    private mutating func replace(_ range: Range<Int>, with replacement: String) {
        var bytes = scalars
        bytes.replaceSubrange(range, with: replacement.unicodeScalars)
        text = String(String.UnicodeScalarView(bytes))
    }
    private func unsafe() -> CommandFailure {
        CommandFailure("invalid_config", "Cannot safely edit this YAML structure. Use ordinary block/flow mappings and quoted or single-line scalar values for config fields; the file was not changed.")
    }
}
