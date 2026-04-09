import AppKit
import QuartzCore

/// NSView that renders a privacy blur over the content behind its window,
/// with a circular "reveal zone" around the mouse position.
///
/// Architecture:
/// - NSVisualEffectView (.underWindowBackground, .darkAqua) provides the GPU-composited blur.
/// - A CAGradientLayer mask (radial, via CGImage) clips the blur to form the reveal hole.
///   This is entirely GPU-resident — no CPU NSImage rendering per frame.
/// - A semi-transparent dark tint overlay (CALayer) adds additional privacy depth.
///   It is clipped by the same shape as the blur (using an identical CAGradientLayer mask copy).
/// - No Screen Recording permission is required; all blending happens against the window compositor.
final class BlurContentView: NSView {

    // MARK: - Public Properties

    /// Tint intensity mapped from the user's 2–20 blur setting.
    var blurRadius: CGFloat = 8.0 {
        didSet { 
            updateTintOpacity()
            updateBlurFilter()
        }
    }

    /// Center of the circular reveal zone in view coordinates.
    var revealCenter: NSPoint? = nil {
        didSet {
            guard revealCenter != oldValue else { return }
            setNeedsUpdateMask()
        }
    }

    /// Radius of the reveal zone in points.
    var revealRadius: CGFloat = 200.0 {
        didSet {
            guard revealRadius != oldValue else { return }
            setNeedsUpdateMask()
        }
    }

    /// Width of the feathered soft edge, as a fraction of `revealRadius` (0.10–0.50).
    /// 0.10 = very sharp; 0.50 = very gradual.
    var featherWidth: CGFloat = 0.28 {
        didSet {
            guard featherWidth != oldValue else { return }
            setNeedsUpdateMask()
        }
    }

    /// Whether reveal follows mouse hover (true) or requires a click (false).
    var revealOnHover: Bool = true

    // MARK: - Private Subviews

    /// Dirty flag — batches multiple property changes into one mask update per runloop turn.
    private var maskUpdateScheduled = false

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
        layer?.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]

        updateBlurFilter()
        updateTintOpacity()
        setNeedsUpdateMask()
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        setNeedsUpdateMask()
    }

    // MARK: - Public API

    /// Update the reveal zone position from a screen-space point.
    /// Called by BlurWindowManager on each mouse-move/click event.
    func updateRevealFromScreenPoint(_ screenPoint: NSPoint) {
        guard let window = self.window else {
            revealCenter = nil
            return
        }
        let windowRect = window.convertFromScreen(NSRect(origin: screenPoint, size: .zero))
        let viewPoint = convert(windowRect.origin, from: nil)
        revealCenter = bounds.contains(viewPoint) ? viewPoint : nil
    }

    // MARK: - Filter Updates

    private func updateBlurFilter() {
        guard let blurFilter = CIFilter(name: "CIGaussianBlur") else { return }
        blurFilter.setDefaults()
        
        // Cap the max blur radius to 100 points
        // Extremely high values (>100) cause macOS CoreImage to physically fail rendering the layer.
        let actualRadius = min(100.0, blurRadius * 5.0)
        blurFilter.setValue(actualRadius, forKey: kCIInputRadiusKey)
        
        // This GPU-accelerated filter samples the screen content behind our window
        // without applying any aggressive macOS window materials. It gives a pure blur.
        layer?.backgroundFilters = [blurFilter]
    }

    // MARK: - Tint Opacity

    /// Maps the user's intensity to a heavy tint (0.50–0.95 alpha).
    /// This fixes the "too transparent" issue by adding significant frosted depth
    /// to completely obliterate white text while staying hardware accelerated.
    private func updateTintOpacity() {
        let normalized = max(0, min(1.0, (blurRadius - 2.0) / 18.0)) // 0.0 … 1.0
        let opacity = 0.50 + normalized * 0.45                       // 0.50 … 0.95
        layer?.backgroundColor = NSColor.black.withAlphaComponent(opacity).cgColor
    }

    // MARK: - Dirty-Flag Mask Scheduling

    /// Schedule a mask update on the next runloop pass — coalesces rapid property changes.
    private func setNeedsUpdateMask() {
        guard !maskUpdateScheduled else { return }
        maskUpdateScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.maskUpdateScheduled = false
            self?.applyMasks()
        }
    }

    // MARK: - GPU-Accelerated Mask

    /// Builds and applies a single `CALayer` mask to the root layer.
    /// Uses a CGImage-based radial gradient — computed once per change, stored in VRAM as a texture.
    private func applyMasks() {
        let size = bounds.size
        guard size.width > 0, size.height > 0 else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)   // no implicit animation on mask changes

        if let center = revealCenter {
            let maskImage = buildRadialMaskCGImage(center: center, size: size)

            // Apply directly to root layer, which clips both the backgroundFilters and the tint
            let maskLayer = CALayer()
            maskLayer.frame = CGRect(origin: .zero, size: size)
            maskLayer.contents = maskImage
            layer?.mask = maskLayer
        } else {
            // No reveal — full-coverage blur everywhere, no mask needed
            layer?.mask = nil
        }

        CATransaction.commit()
    }

    /// Creates an RGBA CGImage mask for the reveal zone.
    ///
    /// CALayer masks use the alpha channel: alpha 1.0 = blur visible, alpha 0.0 = reveal (clear).
    /// The transition happens over `featherWidth * revealRadius` points.
    private func buildRadialMaskCGImage(center: NSPoint, size: NSSize) -> CGImage? {
        let width  = Int(size.width)
        let height = Int(size.height)
        guard width > 0, height > 0 else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // 1. Fill entire mask with opaque black (alpha = 1.0).
        // This makes the whole window blurred by default.
        ctx.setFillColor(red: 0, green: 0, blue: 0, alpha: 1.0)
        ctx.fill(CGRect(origin: .zero, size: size))

        // 2. Switch to .copy blend mode.
        // This forces any drawing to REWRITE the alpha channel completely,
        // rather than blending on top of the opaque background.
        ctx.setBlendMode(.copy)

        // Radial gradient:
        // Center = alpha 0.0 (revealed)
        // Hard stop boundary = alpha 0.0 (revealed)
        // Edge = alpha 1.0 (blurred)
        let hardStop = max(0.0, 1.0 - featherWidth)
        let gradientColors: [CGFloat] = [
            0.0, 0.0, 0.0, 0.0,  // center
            0.0, 0.0, 0.0, 0.0,  // hard stop
            0.0, 0.0, 0.0, 1.0   // edge
        ]
        let locations: [CGFloat] = [0.0, hardStop, 1.0]

        guard let gradient = CGGradient(
            colorSpace: colorSpace,
            colorComponents: gradientColors,
            locations: locations,
            count: 3
        ) else { return nil }

        ctx.addEllipse(in: CGRect(
            x: center.x - revealRadius,
            y: center.y - revealRadius,
            width: revealRadius * 2,
            height: revealRadius * 2
        ))
        ctx.clip()

        ctx.drawRadialGradient(
            gradient,
            startCenter: center, startRadius: 0,
            endCenter: center,   endRadius: revealRadius,
            options: [] // outside the clip stays alpha=1.0 from the fill
        )

        return ctx.makeImage()
    }

}
