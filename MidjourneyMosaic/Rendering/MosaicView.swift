import AppKit
import QuartzCore

@MainActor
final class MosaicView: NSView {
    private final class Slot {
        let container = CALayer()
        var imageLayer: CALayer?
        var itemIndex = 0
    }

    private let rootLayer = CALayer()
    private var items: [MidjourneyItem] = []
    private var slots: [Slot] = []
    private var requestedCount = 0
    private var delay: Double = 2
    private var isAnimating = true
    private var flipTimer: Timer?
    private var loadTasks: [Task<Void, Never>] = []
    private var reloadGeneration = UUID()
    private var spotBag: [Int] = []
    private var nextPoolIndex = 0
    private var flipInProgress = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = rootLayer
        rootLayer.backgroundColor = NSColor.black.cgColor
        rootLayer.masksToBounds = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            flipTimer?.invalidate()
            flipTimer = nil
            loadTasks.forEach { $0.cancel() }
        } else {
            restartTimer()
        }
    }

    override func layout() {
        super.layout()
        rootLayer.frame = bounds
        applyLayout()
    }

    func configure(items: [MidjourneyItem], itemCount: Int, delay: Double, isAnimating: Bool) {
        let clampedCount = min(max(0, itemCount), items.count)
        let needsRebuild = self.items != items || requestedCount != clampedCount
        let timerChanged = self.delay != delay || self.isAnimating != isAnimating

        self.items = items
        self.requestedCount = clampedCount
        self.delay = delay
        self.isAnimating = isAnimating

        if needsRebuild {
            rebuildSlots()
        }
        if needsRebuild || timerChanged {
            restartTimer()
        }
    }

    private func rebuildSlots() {
        reloadGeneration = UUID()
        let generation = reloadGeneration
        flipInProgress = false
        loadTasks.forEach { $0.cancel() }
        loadTasks.removeAll()
        rootLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
        slots.removeAll()
        spotBag.removeAll()
        nextPoolIndex = requestedCount

        guard requestedCount > 0 else { return }

        for index in 0..<requestedCount {
            let slot = Slot()
            slot.itemIndex = index
            slot.container.backgroundColor = placeholderColor(for: items[index].id).cgColor
            slot.container.masksToBounds = true
            slot.container.allowsEdgeAntialiasing = true
            var perspective = CATransform3DIdentity
            perspective.m34 = -0.001
            slot.container.sublayerTransform = perspective
            rootLayer.addSublayer(slot.container)
            slots.append(slot)
            load(itemIndex: index, into: slot, generation: generation, animated: false)
        }

        applyLayout()
    }

    private func applyLayout() {
        guard !slots.isEmpty else { return }
        let ratios = slots.map { CGFloat(items[$0.itemIndex].aspectRatio) }
        let placements = WaterfallMosaicLayout.placements(aspectRatios: ratios, in: bounds, gap: 2)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for placement in placements {
            let slot = slots[placement.itemIndex]
            slot.container.frame = placement.frame
            slot.container.sublayers?.forEach { $0.frame = slot.container.bounds }
        }
        CATransaction.commit()
    }

    private func load(itemIndex: Int, into slot: Slot, generation: UUID, animated: Bool) {
        let item = items[itemIndex]
        let task = Task { [weak self, weak slot] in
            guard let self, let slot else { return }
            do {
                let data = try await ImageDataRepository.shared.data(for: item.imageURL)
                guard !Task.isCancelled,
                      generation == self.reloadGeneration,
                      let image = ImageDecoder.cgImage(from: data) else {
                    self.recoverFromFailedFlip(animated: animated, generation: generation)
                    return
                }
                if animated {
                    self.performFlip(slot: slot, itemIndex: itemIndex, image: image)
                } else {
                    self.install(image: image, itemIndex: itemIndex, in: slot)
                }
            } catch {
                // The deterministic color remains visible if a CDN request fails.
                self.recoverFromFailedFlip(animated: animated, generation: generation)
            }
        }
        loadTasks.append(task)
    }

    private func recoverFromFailedFlip(animated: Bool, generation: UUID) {
        guard animated, generation == reloadGeneration else { return }
        flipInProgress = false
    }

    private func install(image: CGImage, itemIndex: Int, in slot: Slot) {
        guard slot.container.superlayer != nil else { return }
        let imageLayer = makeImageLayer(image: image, bounds: slot.container.bounds)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        slot.imageLayer?.removeFromSuperlayer()
        slot.container.addSublayer(imageLayer)
        slot.imageLayer = imageLayer
        slot.itemIndex = itemIndex
        CATransaction.commit()
    }

    private func makeImageLayer(image: CGImage, bounds: CGRect) -> CALayer {
        let imageLayer = CALayer()
        imageLayer.frame = bounds
        imageLayer.contents = image
        imageLayer.contentsGravity = .resizeAspectFill
        imageLayer.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        imageLayer.masksToBounds = true
        imageLayer.isDoubleSided = false
        return imageLayer
    }

    private func restartTimer() {
        flipTimer?.invalidate()
        flipTimer = nil
        guard isAnimating, requestedCount > 0, items.count > requestedCount else { return }

        // Matches Album Artwork: 0.65 seconds of rotation plus the configured pause.
        flipTimer = Timer.scheduledTimer(withTimeInterval: delay + 0.65, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.requestNextFlip() }
        }
    }

    private func requestNextFlip() {
        guard !flipInProgress, !slots.isEmpty else { return }
        let visible = Set(slots.map(\.itemIndex))
        var selected: (slotIndex: Int, itemIndex: Int)?

        // Replacing like-for-like keeps the best available portrait/square/landscape
        // balance stable instead of gradually drifting into the portrait-heavy tail.
        for _ in slots.indices {
            if spotBag.isEmpty { spotBag = Array(slots.indices).shuffled() }
            guard let slotIndex = spotBag.popLast() else { break }
            let outgoingShape = items[slots[slotIndex].itemIndex].shape
            if let itemIndex = AspectMixing.nextReplacementIndex(
                in: items,
                excluding: visible,
                matching: outgoingShape,
                startingAt: nextPoolIndex
            ) {
                selected = (slotIndex, itemIndex)
                break
            }
        }

        guard let selected else { return }
        nextPoolIndex = (selected.itemIndex + 1) % items.count
        flipInProgress = true
        load(
            itemIndex: selected.itemIndex,
            into: slots[selected.slotIndex],
            generation: reloadGeneration,
            animated: true
        )
    }

    private func performFlip(slot: Slot, itemIndex: Int, image: CGImage) {
        guard let outgoing = slot.imageLayer else {
            install(image: image, itemIndex: itemIndex, in: slot)
            flipInProgress = false
            return
        }

        let incoming = makeImageLayer(image: image, bounds: slot.container.bounds)
        let direction: CGFloat = Bool.random() ? 1 : -1
        let duration: CFTimeInterval = 0.65

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        slot.container.insertSublayer(incoming, below: outgoing)
        slot.container.zPosition = 1
        CATransaction.commit()

        let outgoingAnimation = flipAnimation(
            values: [0, direction * .pi / 2, direction * .pi],
            duration: duration
        )
        let incomingAnimation = flipAnimation(
            values: [-direction * .pi, -direction * .pi / 2, 0],
            duration: duration
        )

        outgoing.add(outgoingAnimation, forKey: "flip")
        incoming.add(incomingAnimation, forKey: "flip")

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self, weak slot, weak outgoing, weak incoming] in
            guard let self else { return }
            defer { self.flipInProgress = false }
            guard let slot, let outgoing, let incoming else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            outgoing.removeFromSuperlayer()
            incoming.removeAllAnimations()
            slot.container.zPosition = 0
            slot.imageLayer = incoming
            slot.itemIndex = itemIndex
            CATransaction.commit()
        }
    }

    private func flipAnimation(values: [CGFloat], duration: CFTimeInterval) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: "transform.rotation.y")
        animation.duration = duration
        animation.repeatCount = 1
        animation.values = values.map { NSNumber(value: Double($0)) }
        animation.keyTimes = [0, 0.5, 1]
        animation.timingFunctions = [
            CAMediaTimingFunction(name: .easeIn),
            CAMediaTimingFunction(name: .easeOut)
        ]
        animation.isRemovedOnCompletion = false
        animation.fillMode = .forwards
        return animation
    }

    private func placeholderColor(for id: String) -> NSColor {
        let hash = id.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) }
        let hue = CGFloat(abs(hash % 360)) / 360
        return NSColor(calibratedHue: hue, saturation: 0.38, brightness: 0.26, alpha: 1)
    }
}
