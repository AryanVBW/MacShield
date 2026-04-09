import SwiftUI
import AppKit

/// Standard animation tokens for MacShield.
/// All animations route through `adapted(_:)` so they automatically
/// respect the system Accessibility > Display > Reduce Motion preference.
enum MacShieldAnimations {

    // MARK: - Reduce-Motion Adapter

    /// Returns the supplied animation as-is, or an instantaneous `.linear(duration: 0)`
    /// when the user has enabled Accessibility > Display > Reduce Motion.
    static func adapted(_ animation: Animation) -> Animation {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            return .linear(duration: 0)
        }
        return animation
    }

    // MARK: - Overlay Tokens

    /// Overlay appears — quick ease-out scale + fade
    static let overlayAppear = Animation.easeOut(duration: 0.22)

    /// Overlay disappears — quick ease-in fade
    static let overlayDisappear = Animation.easeIn(duration: 0.15)

    /// Blur overlay fades in when first shown over a chat app
    static let blurReveal = Animation.easeOut(duration: 0.18)

    /// Blur overlay fades out when dismissed
    static let blurConceal = Animation.easeIn(duration: 0.14)

    /// Full lock screen overlay cross-fades in
    static let overlayFade = Animation.easeOut(duration: 0.25)

    // MARK: - Interaction Tokens

    /// Button press / small tap feedback
    static let buttonPress = Animation.easeInOut(duration: 0.1)

    /// Native-feeling spring shake for wrong password — single call, no DispatchQueue hacks
    static let errorShakeSpring = Animation.interpolatingSpring(stiffness: 600, damping: 15)

    /// Generic transition for UI elements
    static let standard = Animation.easeInOut(duration: 0.2)

    // MARK: - Reveal-Zone Tokens

    /// Smooth reveal zone fade-in when cursor enters
    static let revealIn = Animation.easeOut(duration: 0.12)

    /// Reveal zone fade-out when cursor leaves
    static let revealOut = Animation.easeIn(duration: 0.20)
}
