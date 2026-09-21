import Foundation
import Security

protocol UsageProvider: Sendable {
    func fetch(_ agent: UsageSource, path: String, node: String, secret: String?) async -> UsageSnapshot
}

final class ProcessRegistry: @unchecked Sendable {
    static let shared = ProcessRegistry()
    private let lock = NSLock()
    private var processes: [UUID: Process] = [:]
    private var cancelled: Set<UUID> = []
    func add(_ p: Process, id: UUID) { lock.lock(); defer { lock.unlock() }; processes[id] = p; if cancelled.contains(id), p.isRunning { p.terminate() } }
    func remove(_ id: UUID) { lock.lock(); defer { lock.unlock() }; processes.removeValue(forKey: id); cancelled.remove(id) }
    func cancel(_ id: UUID) { lock.lock(); defer { lock.unlock() }; cancelled.insert(id); if let p = processes[id], p.isRunning { p.terminate() } }
    func cancelAll() { lock.lock(); defer { lock.unlock() }; for p in processes.values where p.isRunning { p.terminate() } }
}

struct CLIProvider: UsageProvider {
    let helper: URL
    func fetch(_ agent: UsageSource, path: String, node: String, secret: String?) async -> UsageSnapshot {
        let id = UUID()
        return await withTaskCancellationHandler {
            await Task.detached(priority: .utility) {
                let process = Process(); let input = Pipe(); let output = Pipe()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
                let home = FileManager.default.homeDirectoryForCurrentUser
                let protectedFolders = [("DESKTOP", "Desktop"), ("DOCUMENTS", "Documents"),
                    ("DOWNLOADS", "Downloads"), ("PICTURES", "Pictures"), ("MOVIES", "Movies"),
                    ("MUSIC", "Music"), ("HOME_GIT", ".git")]
                var arguments: [String] = []
                for (key, folder) in protectedFolders {
                    arguments += ["-D", "\(key)=\(home.appendingPathComponent(folder).resolvingSymlinksInPath().path)"]
                }
                arguments += ["-D", "APP_RESOURCES=\(helper.deletingLastPathComponent().deletingLastPathComponent().resolvingSymlinksInPath().path)"]
                arguments += ["-f", helper.deletingLastPathComponent().appendingPathComponent("query.sb").path,
                              BundledRuntime.python.path, "-I", "-B", helper.path]
                process.arguments = arguments
                process.standardInput = input; process.standardOutput = output
                process.standardError = FileHandle.nullDevice
                var environment = ProcessInfo.processInfo.environment
                environment["PATH"] = BundledRuntime.node.deletingLastPathComponent().path + ":" + "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:\(NSHomeDirectory())/.local/bin"
                // CODEX_HOME must not leak in from the launching shell: the codex CLI
                // hard-fails on a stale path instead of falling back to ~/.codex.
                for key in Array(environment.keys) where key.hasPrefix("PYTHON") || key.hasPrefix("DYLD_") || key == "NODE_OPTIONS" || key == "NODE_PATH" || key == "CODEX_HOME" { environment.removeValue(forKey: key) }
                environment["PYTHONDONTWRITEBYTECODE"] = "1"
                environment["SSL_CERT_FILE"] = BundledRuntime.root.appendingPathComponent("cacert.pem").path
                process.environment = environment
                var config = ["provider": agent.rawValue, "path": path, "node": node, "explicitSecret": "true"]
                if let secret, !secret.isEmpty { config["secret"] = secret }
                defer { ProcessRegistry.shared.remove(id) }
                do {
                    let work = FileManager.default.homeDirectoryForCurrentUser
                        .appendingPathComponent("Library/Application Support/VibeStatistics/QueryWorkspace", isDirectory: true)
                    try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
                    process.currentDirectoryURL = work
                    try process.run(); ProcessRegistry.shared.add(process, id: id)
                    try input.fileHandleForWriting.write(contentsOf: JSONEncoder().encode(config))
                    try input.fileHandleForWriting.close()
                    let deadline = Date().addingTimeInterval(80)
                    while process.isRunning && Date() < deadline { try? await Task.sleep(for: .milliseconds(100)) }
                    if process.isRunning {
                        process.terminate()
                        let grace = Date().addingTimeInterval(5)
                        while process.isRunning && Date() < grace { try? await Task.sleep(for: .milliseconds(100)) }
                        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                        return .failure(agent, code: "timeout", message: "查询超时，稍后自动重试")
                    }
                    let data = output.fileHandleForReading.readDataToEndOfFile()
                    let result = try JSONDecoder().decode(UsageSnapshot.self, from: data)
                    guard result.provider == agent.rawValue else { throw CocoaError(.coderReadCorrupt) }
                    if result.status == "ok" && !result.isValid { throw CocoaError(.coderReadCorrupt) }
                    return result
                } catch {
                    if process.isRunning { process.terminate() }
                    return .failure(agent, code: "bridge", message: "无法读取查询结果，请检查 CLI、Python 和辅助程序")
                }
            }.value
        } onCancel: { ProcessRegistry.shared.cancel(id) }
    }
}

extension UsageSnapshot {
    static func failure(_ agent: UsageSource, code: String, message: String) -> Self {
        Self(provider: agent.rawValue, status: "error", errorCode: code, message: message)
    }
}

@MainActor enum Keychain {
    static let reader = CredentialReader()
    static let service = "com.vibestatistics.credentials"
    static func read(_ agent: UsageSource, allowInteraction: Bool = false) throws -> String? {
        try reader.read(agent, allowInteraction: allowInteraction)
    }
    static func save(_ value: String, for agent: UsageSource) throws {
        try persist(value, for: agent)
        reader.didSave(value, for: agent)
    }
    private static func persist(_ value: String, for agent: UsageSource) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: agent.rawValue]
        if value.isEmpty {
            let code = SecItemDelete(query as CFDictionary)
            guard code == errSecSuccess || code == errSecItemNotFound else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(code)) }
            return
        }
        let data = Data(value.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query; insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let code = SecItemAdd(insert as CFDictionary, nil)
            guard code == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(code)) }
        } else if status != errSecSuccess { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }
}

/// Credentials stay in memory only; polling never requests system authentication UI.
@MainActor final class CredentialReader {
    private(set) var cache: [UsageSource: String] = [:]
    private var failures: [UsageSource: OSStatus] = [:]
    private var missing: Set<UsageSource> = []
    func didSave(_ value: String, for agent: UsageSource) {
        cache[agent] = value.isEmpty ? nil : value
        failures.removeValue(forKey: agent)
        if value.isEmpty { missing.insert(agent) } else { missing.remove(agent) }
    }
    let lookup: ([String: Any]) -> (OSStatus, Data?)
    init(lookup: @escaping ([String: Any]) -> (OSStatus, Data?) = { query in
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, result as? Data)
    }) { self.lookup = lookup }
    func read(_ agent: UsageSource, allowInteraction: Bool = false) throws -> String? {
        if let value = cache[agent] { return value }
        if !allowInteraction {
            if let status = failures[agent] { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
            if missing.contains(agent) { return nil }
        }
        // These credentials live in the legacy login keychain. The per-query UI
        // flag alone only suppresses Data Protection keychain authentication.
        // Keep this synchronous and MainActor-isolated so no app keychain call
        // can interleave while the process-wide legacy UI flag is changed.
        var previous: DarwinBoolean = false
        let getStatus = SecKeychainGetUserInteractionAllowed(&previous)
        guard getStatus == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(getStatus)) }
        let setStatus = SecKeychainSetUserInteractionAllowed(allowInteraction)
        guard setStatus == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(setStatus)) }
        defer { SecKeychainSetUserInteractionAllowed(previous.boolValue) }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Keychain.service, kSecAttrAccount as String: agent.rawValue,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationUI as String: allowInteraction ? kSecUseAuthenticationUIAllow : kSecUseAuthenticationUIFail]
        let (status, data) = lookup(query)
        if status == errSecItemNotFound {
            failures.removeValue(forKey: agent); missing.insert(agent)
            return nil
        }
        guard status == errSecSuccess, let data, let value = String(data: data, encoding: .utf8) else {
            let failure = status == errSecSuccess ? errSecDecode : status
            failures[agent] = failure
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(failure))
        }
        failures.removeValue(forKey: agent); missing.remove(agent)
        cache[agent] = value
        return value
    }
}
