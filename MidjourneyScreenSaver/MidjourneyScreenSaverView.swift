import AppKit
import ScreenSaver

@objc(MidjourneyScreenSaverView)
@MainActor
final class MidjourneyScreenSaverView: ScreenSaverView {
    private enum Keys {
        static let itemCount = "itemCount"
        static let delay = "delay"
    }

    private let mosaicView = MosaicView(frame: .zero)
    private let defaults: ScreenSaverDefaults
    private var settingsController: ScreenSaverSettingsController?

    override init?(frame: NSRect, isPreview: Bool) {
        let bundle = Bundle(for: MidjourneyScreenSaverView.self)
        guard let identifier = bundle.bundleIdentifier,
              let defaults = ScreenSaverDefaults(forModuleWithName: identifier) else {
            return nil
        }

        self.defaults = defaults
        super.init(frame: frame, isPreview: isPreview)

        defaults.register(defaults: [
            Keys.itemCount: MosaicLimits.defaultItemCount,
            Keys.delay: MosaicLimits.defaultDelay
        ])

        animationTimeInterval = 1.0 / 30.0
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        mosaicView.frame = bounds
        mosaicView.autoresizingMask = [.width, .height]
        addSubview(mosaicView)
        applySettings(isAnimating: false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func startAnimation() {
        super.startAnimation()
        applySettings(isAnimating: true)
    }

    override func stopAnimation() {
        applySettings(isAnimating: false)
        super.stopAnimation()
    }

    override func animateOneFrame() {
        // MosaicView owns the low-frequency flip timer and Core Animation owns the
        // frames between flips; the ScreenSaverView timer only keeps the host alive.
    }

    override var hasConfigureSheet: Bool { true }

    override var configureSheet: NSWindow? {
        if let settingsController { return settingsController.window }

        let controller = ScreenSaverSettingsController(
            itemCount: configuredItemCount,
            delay: configuredDelay
        ) { [weak self] itemCount, delay in
            guard let self else { return }
            self.defaults.set(itemCount, forKey: Keys.itemCount)
            self.defaults.set(delay, forKey: Keys.delay)
            self.defaults.synchronize()
            self.applySettings(isAnimating: self.isAnimating)
        }
        settingsController = controller
        return controller.window
    }

    private var configuredItemCount: Int {
        min(
            max(defaults.integer(forKey: Keys.itemCount), MosaicLimits.minimumItemCount),
            MosaicLimits.maximumItemCount
        )
    }

    private var configuredDelay: Double {
        min(
            max(defaults.double(forKey: Keys.delay), MosaicLimits.minimumDelay),
            MosaicLimits.maximumDelay
        )
    }

    private func applySettings(isAnimating: Bool) {
        mosaicView.configure(
            items: StaticExploreSource.load(),
            itemCount: configuredItemCount,
            delay: configuredDelay,
            isAnimating: isAnimating
        )
    }
}

@MainActor
private final class ScreenSaverSettingsController: NSWindowController {
    private let countSlider = NSSlider(
        value: Double(MosaicLimits.defaultItemCount),
        minValue: Double(MosaicLimits.minimumItemCount),
        maxValue: Double(MosaicLimits.maximumItemCount),
        target: nil,
        action: nil
    )
    private let countValue = NSTextField(labelWithString: "")
    private let delaySlider = NSSlider(
        value: MosaicLimits.defaultDelay,
        minValue: MosaicLimits.minimumDelay,
        maxValue: MosaicLimits.maximumDelay,
        target: nil,
        action: nil
    )
    private let delayValue = NSTextField(labelWithString: "")
    private let onSave: (Int, Double) -> Void

    init(itemCount: Int, delay: Double, onSave: @escaping (Int, Double) -> Void) {
        self.onSave = onSave

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 220),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = "Midjourney Mosaic Settings"
        super.init(window: window)

        countSlider.doubleValue = Double(itemCount)
        countSlider.numberOfTickMarks = 0
        countSlider.allowsTickMarkValuesOnly = false
        delaySlider.doubleValue = delay
        delaySlider.numberOfTickMarks = 6
        delaySlider.allowsTickMarkValuesOnly = true
        countSlider.target = self
        countSlider.action = #selector(updateLabels)
        delaySlider.target = self
        delaySlider.action = #selector(updateLabels)

        window.contentView = makeContentView()
        updateLabels()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func makeContentView() -> NSView {
        let countRow = makeRow(title: "Images", slider: countSlider, value: countValue)
        let delayRow = makeRow(title: "Pause", slider: delaySlider, value: delayValue)

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancelButton.keyEquivalent = "\u{1b}"
        let saveButton = NSButton(title: "Save", target: self, action: #selector(save))
        saveButton.keyEquivalent = "\r"
        saveButton.bezelStyle = .rounded

        let buttons = NSStackView(views: [NSView(), cancelButton, saveButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        let stack = NSStackView(views: [countRow, delayRow, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 26),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        return content
    }

    private func makeRow(title: String, slider: NSSlider, value: NSTextField) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.widthAnchor.constraint(equalToConstant: 58).isActive = true
        value.alignment = .right
        value.monospacedDigitFont()
        value.widthAnchor.constraint(equalToConstant: 78).isActive = true

        let row = NSStackView(views: [label, slider, value])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.widthAnchor.constraint(equalToConstant: 392).isActive = true
        return row
    }

    @objc private func updateLabels() {
        countValue.stringValue = "\(countSlider.integerValue)"
        delayValue.stringValue = "\(delaySlider.integerValue) sec"
    }

    @objc private func cancel() {
        guard let window else { return }
        if let parent = window.sheetParent {
            parent.endSheet(window)
        } else {
            window.close()
        }
    }

    @objc private func save() {
        onSave(countSlider.integerValue, delaySlider.doubleValue)
        guard let window else { return }
        if let parent = window.sheetParent {
            parent.endSheet(window)
        } else {
            window.close()
        }
    }
}

private extension NSTextField {
    func monospacedDigitFont() {
        font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    }
}
