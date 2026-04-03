import AppKit

/// NSView that renders a privacy blur over the content behind its window,
/// with a circular "reveal zone" around the mouse position.
///
/// Uses NSVisualEffectView with .behindWindow blending — no screen capture
/// or Screen Recording permission required. GPU-accelerated and always in sync.
final class BlurContentView: NSView {

    /// Controls tint darkness (mapped from user's 2–20 intensity setting).
    var blurRadius: CGFloat = 8.0 {
        didSet { updateTintOpacity() }
    }

    /// Center of the circular reveal zone (view coordinates).
    var revealCenter: NSPoint? = nil {
        didSet { updateRevealMask() }
    }

    /// Radius of the reveal zone in points.
    var revealRadius: CGFloat = 200.0 {
        didSet { updateRevealMask() }
    }

    /// true = reveal follows mouse hover; false = reveal on click.
    var revealOnHover: Bool = true

    // MARK: - Subviews

    private let visualEffectView = NSVisualEffectView()
    private let tintOverlay = NSView()

    // MARK: - Init

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    // MARK: - Setup

    private func setup() {
        wantsLayer = true

        // --- Visual effect (system blur of content behind this window) ---
        visualEffectView.material = .fullScreenUI
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.appearance = NSAppearance(named: .darkAqua)
        visualEffectView.frame = bounds
        visualEffectView.autoresizingMask = [.width, .height]
        addSubview(visualEffectView)

        // --- Tint overlay for additional privacy / intensity control ---
        tintOverlay.wantsLayer = true
        tintOverlay.frame = bounds
        tintOverlay.autoresizingMask = [.width, .height]
        addSubview(tintOverlay)

        updateTintOpacity()
    }

    // MARK: - Public

    /// Update the reveal zone position from a screen-space point.
    /// Called by BlurWindowManager on each refresh tick.
    func updateRevealFromScreenPoint(_ screenPoint: NSPoint) {
        guard let window = self.window else {
            revealCenter = nil
            return
        }
        let windowRect = window.convertFromScreen(NSRect(origin: screenPoint, size: .zero))
        let viewPoint = convert(windowRect.origin, from: nil)

        if bounds.contains(viewPoint) {
            revealCenter = viewPoint
        } else {
            revealCenter = nil
        }
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        updateRevealMask()
    }

    // MARK: - Reveal Mask

    /// Updates both the NSVisualEffectView mask and the tint overlay mask
    /// to create a circular reveal zone with a soft gradient edge.
    private func updateRevealMask() {
        let size = bounds.size
        guard size.width > 0, size.height > 0 else { return }

        if let center = revealCenter {
            // --- Visual effect view: maskImage with soft gradient edge ---
            visualEffectView.maskImage = createSoftMaskImage(center: center, size: size)

            // --- Tint overlay: CAShapeLayer mask (hard circle, slightly smaller) ---
            let tintMask = CAShapeLayer()
            tintMask.frame = CGRect(origin: .zero, size: size)
            let path = CGMutablePath()
            path.addRect(CGRect(origin: .zero, size: size))
            // Use 80% of revealRadius for the tint cutout to match the soft edge
            let effectiveRadius = revealRadius * 0.8
            let revealRect = CGRect(
                x: center.x - effectiveRadius,
                y: center.y - effectiveRadius,
                width: effectiveRadius * 2,
                height: effectiveRadius * 2
            )
            path.addEllipse(in: revealRect)
            tintMask.path = path
            tintMask.fillRule = .evenOdd
            tintMask.fillColor = NSColor.white.cgColor
            tintOverlay.layer?.mask = tintMask
        } else {
            // No reveal — full blur everywhere
            visualEffectView.maskImage = nil   // nil = no mask = effect covers everything
            tintOverlay.layer?.mask = nil       // full tint
        }
    }

    /// Creates an NSImage mask for the visual effect view.
    /// White regions = blurred; black regions = clear (show-through).
    /// Uses a radial gradient for a soft edge on the reveal circle.
    private func createSoftMaskImage(center: NSPoint, size: NSSize) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        guard let ctx = NSGraphicsContext.current?.cgContext else { return image }

        // Fill white = effect visible everywhere
        ctx.setFillColor(CGColor.white)
        ctx.fill(CGRect(origin: .zero, size: size))

        // Punch the reveal zone with a radial gradient:
        //   center → 70% radius: black (fully clear)
        //   70% radius → 100% radius: gradient black→white (soft edge)
        ctx.saveGState()

        // Clip to the reveal circle so the gradient doesn't spill
        let revealRect = CGRect(
            x: center.x - revealRadius,
            y: center.y - revealRadius,
            width: revealRadius * 2,
            height: revealRadius * 2
        )
        ctx.addEllipse(in: revealRect)
        ctx.clip()

        let colorSpace = CGColorSpaceCreateDeviceGray()
        let colors: [CGFloat] = [
            0, 1,    // black, full alpha (center — clear)
            0, 1,    // black, full alpha (70% — still clear)
            1, 1     // white, full alpha (edge — blurred)
        ]
        let locations: [CGFloat] = [0.0, 0.7, 1.0]

        if let gradient = CGGradient(
            colorSpace: colorSpace,
            colorComponents: colors,
            locations: locations,
            count: 3
        ) {
            ctx.drawRadialGradient(
                gradient,
                startCenter: center,
                startRadius: 0,
                endCenter: center,
                endRadius: revealRadius,
                options: []
            )
        }

        ctx.restoreGState()
        return image
    }

    // MARK: - Tint

    /// Maps the user's blur intensity (2–20) to a tint opacity (0.05–0.45).
    private func updateTintOpacity() {
        let normalized = (blurRadius - 2.0) / 18.0   // 0.0 … 1.0
        let opacity = 0.05 + normalized * 0.40        // 0.05 … 0.45
        tintOverlay.layer?.backgroundColor = NSColor.black.withAlphaComponent(CGFloat(opacity)).cgColor
    }
}
