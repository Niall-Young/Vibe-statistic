import AppKit
import CryptoKit
import SwiftUI

struct UpdateRelease: Equatable {
    let version: String
    let notes: String
    let zipURL: URL
    let sha256URL: URL?
}

struct UpdaterError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

@MainActor final class AppUpdater: ObservableObject {
    static let shared = AppUpdater()
    enum Phase: Equatable {
        case idle, checking, upToDate, available(UpdateRelease), downloading(Double), installing, error(String)
    }
    @Published var phase: Phase = .idle

    private let apiURL = URL(string: "https://api.github.com/repos/Niall-Young/Vibe-statistic/releases/latest")!

    var currentVersion: String? {
        guard let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String, !version.isEmpty else { return nil }
        return version
    }

    private var busy: Bool {
        switch phase { case .checking, .downloading, .installing: return true; default: return false }
    }

    nonisolated static func isNewer(_ candidate: String, than current: String) -> Bool {
        func parts(_ value: String) -> [Int] {
            var text = value
            if text.hasPrefix("v") { text.removeFirst() }
            return text.split(separator: ".").compactMap { Int($0) }
        }
        let left = parts(candidate), right = parts(current)
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a > b }
        }
        return false
    }

    // 菜单栏入口：检查后用系统弹窗展示结果，安装期间显示模态进度。
    func checkFromMenu() {
        if busy {
            runAlert("正在检查或下载更新", "进度可在主窗口「设置 · 关于与更新」中查看。")
            return
        }
        Task { @MainActor in
            do {
                guard let current = try prepareCheck() else { return }
                guard let release = try await fetchLatest() else {
                    throw UpdaterError(message: "GitHub 最新发布中没有找到 arm64 安装包")
                }
                guard Self.isNewer(release.version, than: current) else {
                    phase = .upToDate
                    runAlert("已是最新版本", "当前版本 \(current) 已是最新。")
                    return
                }
                phase = .available(release)
                promptInstall(release, current: current)
            } catch {
                fail(error)
                runAlert("检查更新失败", message(of: error))
            }
        }
    }

    // 设置页入口：只更新 phase，由 SwiftUI 内联展示。
    func checkForUpdates(userInitiated: Bool) {
        if busy { return }
        Task { @MainActor in
            do {
                guard let current = try prepareCheck() else { return }
                guard let release = try await fetchLatest() else {
                    throw UpdaterError(message: "GitHub 最新发布中没有找到 arm64 安装包")
                }
                phase = Self.isNewer(release.version, than: current) ? .available(release) : .upToDate
            } catch {
                if userInitiated { fail(error) } else { phase = .idle }
            }
        }
    }

    func downloadAndInstall(_ release: UpdateRelease) {
        guard !busy else { return }
        Task { @MainActor in
            do { try await performInstall(release) }
            catch { fail(error) }
        }
    }

    // MARK: - 检查

    private func prepareCheck() throws -> String? {
        if PublicPreview.enabled {
            phase = .error("预览模式不支持检查更新")
            return nil
        }
        guard let current = currentVersion else {
            phase = .error("开发构建没有版本号，无法检查更新；请使用正式安装包")
            return nil
        }
        phase = .checking
        return current
    }

    private func fetchLatest() async throws -> UpdateRelease? {
        var request = URLRequest(url: apiURL)
        request.setValue("Vibe-Statistics", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UpdaterError(message: "网络响应异常") }
        switch http.statusCode {
        case 200: break
        case 404: throw UpdaterError(message: "该仓库尚未发布任何 Release")
        default: throw UpdaterError(message: "GitHub 返回状态码 \(http.statusCode)")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let assets = json["assets"] as? [[String: Any]] else {
            throw UpdaterError(message: "无法解析发布信息")
        }
        var version = tag
        if version.hasPrefix("v") { version.removeFirst() }
        func assetURL(named name: String) -> URL? {
            (assets.first { ($0["name"] as? String) == name }?["browser_download_url"] as? String).flatMap(URL.init(string:))
        }
        let zipName = assets.compactMap { $0["name"] as? String }
            .first { $0.hasSuffix("-arm64.zip") && !$0.hasSuffix(".sha256") }
        guard let zipName, let zipURL = assetURL(named: zipName) else { return nil }
        return UpdateRelease(version: version,
                             notes: (json["body"] as? String) ?? "",
                             zipURL: zipURL,
                             sha256URL: assetURL(named: zipName + ".sha256"))
    }

    // MARK: - 下载与安装

    private func performInstall(_ release: UpdateRelease, progress: ((Double) -> Void)? = nil) async throws {
        phase = .downloading(0)
        let staging = FileManager.default.temporaryDirectory.appending(path: "VibeUpdate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        let zip = staging.appending(path: "release.zip")
        try await download(release.zipURL, to: zip) { fraction in
            Task { @MainActor in
                self.phase = .downloading(fraction)
                progress?(fraction)
            }
        }
        if let sha256URL = release.sha256URL {
            let checksumFile = staging.appending(path: "release.zip.sha256")
            try await download(sha256URL, to: checksumFile)
            let expected = try String(contentsOf: checksumFile, encoding: .utf8)
                .split(whereSeparator: \.isWhitespace).first.map(String.init)?.lowercased() ?? ""
            let digest = SHA256.hash(data: try Data(contentsOf: zip, options: .mappedIfSafe))
            let actual = digest.map { String(format: "%02x", $0) }.joined()
            guard !expected.isEmpty, expected == actual else {
                throw UpdaterError(message: "SHA-256 校验失败，已取消安装")
            }
        }
        phase = .installing
        let extract = staging.appending(path: "extract")
        try FileManager.default.createDirectory(at: extract, withIntermediateDirectories: true)
        try await runDitto(["-x", "-k", zip.path, extract.path])
        guard let newApp = try FileManager.default.contentsOfDirectory(at: extract, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension == "app" }) else {
            throw UpdaterError(message: "更新包中未找到应用")
        }
        try swapIn(newApp)
    }

    private func download(_ url: URL, to file: URL, progress: ((Double) -> Void)? = nil) async throws {
        let (bytes, response) = try await URLSession.shared.bytes(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdaterError(message: "下载安装包失败（\(url.lastPathComponent)）")
        }
        FileManager.default.createFile(atPath: file.path, contents: nil)
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        let total = Double(http.expectedContentLength > 0 ? http.expectedContentLength : 0)
        var received = 0.0
        var buffer = Data()
        buffer.reserveCapacity(256 * 1024)
        for try await byte in bytes {
            buffer.append(byte)
            received += 1
            if buffer.count >= 256 * 1024 {
                try handle.write(contentsOf: buffer)
                buffer.removeAll(keepingCapacity: true)
                if total > 0 { progress?(min(received / total, 1)) }
            }
        }
        try handle.write(contentsOf: buffer)
        progress?(1)
    }

    private func runDitto(_ arguments: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = arguments
            process.terminationHandler = { finished in
                if finished.terminationStatus == 0 { continuation.resume() }
                else { continuation.resume(throwing: UpdaterError(message: "解压失败（ditto 退出码 \(finished.terminationStatus)）")) }
            }
            do { try process.run() }
            catch { continuation.resume(throwing: UpdaterError(message: "无法启动 ditto：\(error.localizedDescription)")) }
        }
    }

    private func swapIn(_ newApp: URL) throws {
        let files = FileManager.default
        let current = Bundle.main.bundleURL
        let parent = current.deletingLastPathComponent()
        guard files.isWritableFile(atPath: parent.path) else {
            throw UpdaterError(message: "无法写入应用所在目录（\(parent.path)），请手动替换更新")
        }
        // 清理上一次更新留下的旧版本备份
        let backups = (try? files.contentsOfDirectory(at: files.temporaryDirectory, includingPropertiesForKeys: nil)) ?? []
        for old in backups where old.lastPathComponent.hasPrefix("VibeStatistics-old-") {
            try? files.removeItem(at: old)
        }
        let backup = files.temporaryDirectory.appending(path: "VibeStatistics-old-\(UUID().uuidString)")
        let staged = parent.appending(path: ".vibe-update-\(UUID().uuidString)")
        try files.moveItem(at: newApp, to: staged)
        do { try files.moveItem(at: current, to: backup) }
        catch {
            try? files.removeItem(at: staged)
            throw UpdaterError(message: "无法移走当前版本（\(error.localizedDescription)）")
        }
        do { try files.moveItem(at: staged, to: current) }
        catch {
            try? files.moveItem(at: backup, to: current)
            try? files.removeItem(at: staged)
            throw UpdaterError(message: "替换应用失败，已尝试恢复原版本")
        }
        relaunch(current)
    }

    private func relaunch(_ url: URL) {
        Task { @MainActor in
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = true
            _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            NSApp.terminate(nil)
        }
    }

    // MARK: - 弹窗流程

    private func promptInstall(_ release: UpdateRelease, current: String) {
        let alert = NSAlert()
        alert.messageText = "发现新版本 \(release.version)（当前 \(current)）"
        var text = "将下载官方 GitHub Release 安装包，校验 SHA-256 后自动替换并重新启动应用。"
        let notes = release.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty { text = String(notes.prefix(500)) + "\n\n" + text }
        alert.informativeText = text
        alert.addButton(withTitle: "下载并安装")
        alert.addButton(withTitle: "稍后")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        installWithModalProgress(release)
    }

    private func installWithModalProgress(_ release: UpdateRelease) {
        let alert = NSAlert()
        alert.messageText = "正在下载更新…"
        alert.informativeText = "下载完成后会自动校验并替换应用，然后重新启动。"
        let bar = NSProgressIndicator(frame: NSRect(x: 0, y: 0, width: 260, height: 6))
        bar.style = .bar
        bar.minValue = 0
        bar.maxValue = 1
        alert.accessoryView = bar
        alert.addButton(withTitle: "在后台继续")
        Task { @MainActor in
            do { try await performInstall(release, progress: { fraction in bar.doubleValue = fraction }) }
            catch {
                NSApp.stopModal()
                fail(error)
                runAlert("更新失败", message(of: error))
            }
        }
        alert.runModal()
        // 点击「在后台继续」后任务照常执行，进度可在设置页查看。
    }

    private func runAlert(_ title: String, _ body: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body
        alert.runModal()
    }

    private func fail(_ error: Error) {
        phase = .error(message(of: error))
    }

    private func message(of error: Error) -> String {
        (error as? UpdaterError)?.message ?? error.localizedDescription
    }
}
