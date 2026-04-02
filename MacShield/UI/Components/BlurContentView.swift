import AppKit
import CoreImage

/// NSView that renders a blurred version of the content behind it,
/// with a circular "reveal zone" around the mouse position.
final class BlurContentView: NSView {
    var blurRadius: CGFloat = 8.0 {
        didSet { needsDisplay = true }
    }
    var revealCenter: NSPoint? = nil {
        didSet { needsDisplay = true }
    }
    var revealRadius: CGFloat = 200.0 {
        didSet { needsDisplay = true }
    }
    var revealOnHover: Bool = true

    /// The window ID of the target app window we are blurring.
    var targetWindowID: CGWindowID = 0

    private var trackingArea: NSTrackingArea?
    private let ciContext = CIContext()
    private var isRevealed = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupTracking()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupTracking()
    }

    private func setupTracking() {
        updateTrackingArea()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        updateTrackingArea()
    }

    private func updateTrackingArea() {
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    // MARK: - Mouse Tracking

    override func mouseMoved(with event: NSEvent) {
        if revealOnHover {
            revealCenter = convert(event.locationInWindow, from: nil)
        }
    }

    override func mouseDown(with event: NSEvent) {
        if !revealOnHover {
            let point = convert(event.locationInWindow, from: nil)
            if isRevealed && revealCenter == point {
                // Second click hides
                revealCenter = nil
                isRevealed = false
            } else {
                revealCenter = point
                isRevealed = true
            }
        }
    }

    override func mouseExited(with event: NSEvent) {
        if revealOnHover {
            revealCenter = nil
        }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Capture the content behind this overlay window.
        // We need the target app's window content — use CGWindowListCreateImage
        // to capture just that window.
        guard targetWindowID != 0 else {
            // Fallback: draw a solid frosted overlay
            drawFallbackBlur(in: context, dirtyRect: dirtyRect)
            return
        }

        // Get the overlay window's screen position
        guard let overlayWindow = self.window else {
            drawFallbackBlur(in: context, dirtyRect: dirtyRect)
            return
        }

        let windowFrame = overlayWindow.frame

        // Capture the target window content
        let captureRect = windowFrame
        guard let cgImage = CGWindowListCreateImage(
            captureRect,
            .optionIncludingWindow,
            targetWindowID,
            [.boundsIgnoreFraming, .nominalResolution]
        ) else {
            drawFallbackBlur(in: context, dirtyRect: dirtyRect)
            return
        }

        let ciImage = CIImage(cgImage: cgImage)

        // Apply Gaussian blur
        guard let blurFilter = CIFilter(name: "CIGaussianBlur") else {
            drawFallbackBlur(in: context, dirtyRect: dirtyRect)
            return
        }
        blurFilter.setValue(ciImage, forKey: kCIInputImageKey)
        blurFilter.setValue(blurRadius, forKey: kCIInputRadiusKey)

        guard let blurredImage = blurFilter.outputImage else {
            drawFallbackBlur(in: context, dirtyRect: dirtyRect)
            return
        }

        // Render the blurred image
        let extent = ciImage.extent
        guard let renderedImage = ciContext.createCGImage(blurredImage, from: extent) else {
            drawFallbackBlur(in: context, dirtyRect: dirtyRect)
            return
        }

        // Draw the blurred image filling the view
        context.saveGState()
        context.draw(renderedImage, in: bounds)

        // If there's a reveal center, cut a circular hole and draw the original (unblurred) image there
        if let center = revealCenter {
            // Clip to a circle and draw the original unblurred content
            let revealRect = CGRect(
                x: center.x - revealRadius,
                y: center.y - revealRadius,
                width: revealRadius * 2,
                height: revealRadius * 2
            )

            // Create a soft-edge reveal using a radial gradient mask
            context.saveGState()

            // Use an ellipse clip for the reveal zone
            let path = CGPath(ellipseIn: revealRect, transform: nil)
            context.addPath(path)
            context.clip()

            // Draw the original (unblurred) content in the reveal zone
            context.draw(cgImage, in: bounds)

            context.restoreGState()
        }

        // Draw a subtle dark tint over the blurred area (outside the reveal)
        context.setFillColor(NSColor.black.withAlphaComponent(0.15).cgColor)
        if let center = revealCenter {
            // Fill everything except the reveal circle
            let fullPath = CGMutablePath()
            fullPath.addRect(bounds)
            let revealRect = CGRect(
                x: center.x - revealRadius,
                y: center.y - revealRadius,
                width: revealRadius * 2,
                height: revealRadius * 2
            )
            fullPath.addEllipse(in: revealRect)
            context.addPath(fullPath)
            context.fillPath(using: .evenOdd)
        } else {
            context.fill(bounds)
        }

        context.restoreGState()
    }

    /// Fallback blur using NSVisualEffectView-style solid overlay.
    private func drawFallbackBlur(in context: CGContext, dirtyRect: NSRect) {
        // Draw a frosted dark overlay when we can't capture the window content
        context.saveGState()

        // Semi-transparent dark background
        context.setFillColor(NSColor.black.withAlphaComponent(0.7).cgColor)
        context.fill(dirtyRect)

        // If there's a reveal center, cut a hole
        if let center = revealCenter {
            context.setBlendMode(.clear)
            let revealRect = CGRect(
                x: center.x - revealRadius,
                y: center.y - revealRadius,
                width: revealRadius * 2,
                height: revealRadius * 2
            )
            context.fillEllipse(in: revealRect)
        }

        context.restoreGState()
    }
}
