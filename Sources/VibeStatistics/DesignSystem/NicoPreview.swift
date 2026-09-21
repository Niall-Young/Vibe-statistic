import AppKit
import SwiftUI

@MainActor enum NicoPreview {
    /// A preview entry point that never constructs UsageStore or queries an account.
    static func start(delegate: AppDelegate) -> Bool {
        guard CommandLine.arguments.contains("--nico-gallery") || CommandLine.arguments.contains("--nico-render") else { return false }
        _ = Nico.registerFonts
        if let index = CommandLine.arguments.firstIndex(of: "--nico-render"), CommandLine.arguments.indices.contains(index + 1) {
            do {
                let directory = URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try renderSamples(to: directory)
                print("Native Nico samples: \(directory.path)")
            } catch { fputs("Nico render failed: \(error)\n", stderr); exit(1) }
            NSApp.terminate(nil)
            return true
        }
        NSApp.setActivationPolicy(.regular)
        let window = NSWindow(contentRect: NSRect(x:0,y:0,width:1200,height:880),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        window.title = "Nico · 原生设计系统"
        let controller = NSHostingController(rootView:NicoCatalog())
        controller.sizingOptions = []
        window.contentViewController = controller
        window.setContentSize(NSSize(width:1200,height:880))
        window.minSize = NSSize(width:1000,height:720)
        window.isReleasedWhenClosed = false; window.center()
        delegate.window = window
        let menu = NSMenu(); let item = NSMenuItem(); menu.addItem(item)
        let appMenu = NSMenu(); item.submenu = appMenu
        appMenu.addItem(withTitle:"退出组件预览",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
        let edit = NSMenu(); let editItem = NSMenuItem(); editItem.title = "编辑"; editItem.submenu = edit; menu.addItem(editItem)
        edit.addItem(withTitle:"剪切",action:#selector(NSText.cut(_:)),keyEquivalent:"x")
        edit.addItem(withTitle:"拷贝",action:#selector(NSText.copy(_:)),keyEquivalent:"c")
        edit.addItem(withTitle:"粘贴",action:#selector(NSText.paste(_:)),keyEquivalent:"v")
        edit.addItem(withTitle:"全选",action:#selector(NSText.selectAll(_:)),keyEquivalent:"a")
        NSApp.mainMenu = menu
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
        return true
    }
    static func renderSamples(to directory: URL) throws {
        var report: [[String:Any]] = []
        for item in Nico.inventory where !item.objects("sets").isEmpty || !item.objects("single").isEmpty {
            let page = NicoLibrary.page(item.string("id"))
            let samples = page.sets.flatMap { [$0.variants[0], $0.variants[$0.variants.count - 1]] } + page.singles
            for variant in samples {
                let node = page.nodes[variant.root]
                let size = CGSize(width: max(1,node.double("width")),height:max(1,node.double("height")))
                guard size.width < 4096 && size.height < 4096 else { continue }
                for dark in [false,true] {
                    let view = NicoDrawingView(frame:NSRect(origin:.zero,size:size))
                    view.page = page; view.root = variant.root; view.mode = .init(dark:dark)
                    let image = NSImage(size:size,flipped:true) { rect in
                        Nico.nsColor("--color-surface",mode:.init(dark:dark)).setFill(); rect.fill()
                        view.draw(rect); return true
                    }
                    guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data:tiff), let png = rep.representation(using:.png,properties:[:]) else { throw CocoaError(.fileWriteUnknown) }
                    let name = variant.id.replacingOccurrences(of:":",with:"-") + (dark ? "-dark" : "-light") + ".png"
                    try png.write(to:directory.appendingPathComponent(name))
                    report.append(["id":variant.id,"page":page.name,"file":name,"width":size.width,"height":size.height])
                }
            }
        }
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:directory.appendingPathComponent("report.json"))
    }
}
