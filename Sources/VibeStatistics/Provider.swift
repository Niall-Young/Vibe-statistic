import Foundation
import Security

protocol UsageProvider: Sendable {
    func fetch(_ agent: Agent, path: String, node: String, secret: String?) async -> UsageSnapshot
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
    func fetch(_ agent: Agent, path: String, node: String, secret: String?) async -> UsageSnapshot {
        let id = UUID()
        return await withTaskCancellationHandler {
            await Task.detached(priority: .utility) {
                let process = Process(); let input = Pipe(); let output = Pipe()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
                process.arguments = [helper.path]
                process.standardInput = input; process.standardOutput = output
                process.standardError = FileHandle.nullDevice
                var environment = ProcessInfo.processInfo.environment
                environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:\(NSHomeDirectory())/.local/bin"
                environment["PYTHONDONTWRITEBYTECODE"] = "1"
                process.environment = environment
                var config = ["provider": agent.rawValue, "path": path, "node": node]
                if let secret, !secret.isEmpty { config["secret"] = secret }
                defer { ProcessRegistry.shared.remove(id) }
                do {
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
    static func failure(_ agent: Agent, code: String, message: String) -> Self {
        Self(provider: agent.rawValue, status: "error", errorCode: code, message: message)
    }
}

enum Keychain {
    static let service = "com.vibestatistics.credentials"
    static func read(_ agent: Agent) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: agent.rawValue, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func save(_ value: String, for agent: Agent) throws {
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
