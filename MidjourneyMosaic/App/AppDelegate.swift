import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = MosaicSettings()
    private var panel: PreviewPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let options = LaunchOptions(arguments: CommandLine.arguments)
        settings.itemCount = options.itemCount
        settings.delay = options.delay
        settings.showsControls = !options.hideControls

        let content = ContentView(settings: settings)
        let host = NSHostingController(rootView: content)
        let panel = PreviewPanel(
            contentRect: NSRect(x: 0, y: 0, width: options.width, height: options.height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.title = "Midjourney Mosaic — Prototype"
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .black
        panel.isOpaque = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentViewController = host
        panel.minSize = NSSize(width: 520, height: 360)
        panel.contentMinSize = NSSize(width: 520, height: 360)
        panel.orderFrontRegardless()
        panel.setContentSize(NSSize(width: options.width, height: options.height))
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let visible = screen.visibleFrame
            let frame = panel.frame
            panel.setFrameOrigin(NSPoint(
                x: visible.midX - frame.width / 2,
                y: visible.midY - frame.height / 2
            ))
        }
        self.panel = panel
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

private final class PreviewPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct LaunchOptions {
    var width: CGFloat = 1180
    var height: CGFloat = 760
    var itemCount = MosaicLimits.defaultItemCount
    var delay = MosaicLimits.defaultDelay
    var hideControls = false

    init(arguments: [String]) {
        var iterator = arguments.dropFirst().makeIterator()
        while let argument = iterator.next() {
            switch argument {
            case "--width":
                if let value = iterator.next(), let parsed = Double(value) { width = max(520, parsed) }
            case "--height":
                if let value = iterator.next(), let parsed = Double(value) { height = max(360, parsed) }
            case "--items":
                if let value = iterator.next(), let parsed = Int(value) {
                    itemCount = min(max(parsed, MosaicLimits.minimumItemCount), MosaicLimits.maximumItemCount)
                }
            case "--delay":
                if let value = iterator.next(), let parsed = Double(value) {
                    delay = min(max(parsed, MosaicLimits.minimumDelay), MosaicLimits.maximumDelay)
                }
            case "--hide-controls":
                hideControls = true
            default:
                continue
            }
        }
    }
}
