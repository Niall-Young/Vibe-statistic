import Foundation
import CryptoKit

/// A service is independent of the installed tool displaying its account quota.
enum UsageSource: String, CaseIterable, Codable, Sendable, Identifiable {
    case codex, kimi, qoder, deepseek, glm, antigravity
    var id: String { rawValue }
    var isAPI: Bool { self == .deepseek || self == .glm }
    var needsSecret: Bool { isAPI || self == .qoder }
    var title: String {
        switch self {
        case .codex: "Codex 官方账户"
        case .kimi: "Kimi 官方账户"
        case .qoder: "Qoder CN 官方账户"
        case .deepseek: "DeepSeek API"
        case .glm: "智谱 GLM Coding Plan"
        case .antigravity: "Antigravity 官方账户"
        }
    }
    var portal: URL {
        URL(string: self == .glm ? "https://bigmodel.cn/" : self == .deepseek ? "https://platform.deepseek.com/usage" : Agent(rawValue: rawValue)!.portal.absoluteString)!
    }
}

extension Agent {
    var nativeSource: UsageSource { UsageSource(rawValue: rawValue)! }
    var sources: [UsageSource] {
        if self == .antigravity { return [.antigravity] }
        if self == .deepseek { return [.deepseek, .glm] }
        return [nativeSource, .deepseek, .glm]
    }
    var executableNames: [String] {
        switch self {
        case .codex: ["codex"]
        case .kimi: ["kimi"]
        case .qoder: ["qodercn", "qoderclicn"]
        case .deepseek: ["claude"]
        case .antigravity: ["agy"]
        }
    }
}

struct AgentDetector {
    var home: URL = FileManager.default.homeDirectoryForCurrentUser
    var environmentPath: String = ProcessInfo.processInfo.environment["PATH"] ?? ""
    var executable: (String) -> Bool = { path in
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &directory)
            && !directory.boolValue && FileManager.default.isExecutableFile(atPath: path)
    }
    func resolve(_ agent: Agent, custom: String?) -> String? {
        func expand(_ path: String) -> String {
            path.hasPrefix("~/") ? home.appendingPathComponent(String(path.dropFirst(2))).path : path
        }
        // An explicit broken path remains an error, rather than silently selecting another install.
        if let custom, !custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let path = expand(custom)
            guard path.hasPrefix("/") else { return nil }
            return executable(path) ? URL(fileURLWithPath: path).resolvingSymlinksInPath().path : nil
        }
        let directories = [home.appendingPathComponent(".local/bin").path,
            "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
            + environmentPath.split(separator: ":").map(String.init).filter { $0.hasPrefix("/") }
        var candidates = [expand(agent.defaultPath)]
        if agent == .qoder { candidates += [home.appendingPathComponent(".qoder-cn/bin/qoderclicn/qoderclicn").path] }
        candidates += directories.flatMap { directory in agent.executableNames.map { directory + "/" + $0 } }
        return candidates.first(where: executable).map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }
    }
}

struct ClaudeAPIConfiguration {
    let source: UsageSource
    let secret: String?
    static func read(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Self? {
        guard let data = try? Data(contentsOf: home.appendingPathComponent(".claude/settings.json")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let env = json["env"] as? [String: Any],
              let address = env["ANTHROPIC_BASE_URL"] as? String,
              let url = URL(string: address), url.scheme == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443 else { return nil }
        let source: UsageSource
        switch url.host?.lowercased() {
        case "api.deepseek.com": source = .deepseek
        case "open.bigmodel.cn": source = .glm
        default: return nil
        }
        let key = (env["ANTHROPIC_AUTH_TOKEN"] as? String) ?? (env["ANTHROPIC_API_KEY"] as? String)
        return Self(source: source, secret: key?.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

struct QueryIdentity: Hashable, Sendable {
    let source: UsageSource
    let account: String
    static func fingerprint(_ secret: String) -> String {
        SHA256.hash(data: Data(secret.utf8)).map { String(format: "%02x", $0) }.joined().prefix(20).description
    }
}

enum BundledRuntime {
    static var root: URL { Bundle.main.resourceURL!.appendingPathComponent("Runtime") }
    static var python: URL { root.appendingPathComponent("python/bin/python3") }
    static var node: URL { root.appendingPathComponent("node/bin/node") }
}
