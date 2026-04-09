import SwiftUI
import AppKit

/// NSVisualEffectView wrapper for SwiftUI blur backgrounds.
///
/// Default configuration uses .fullScreenUI material (strongest blur) with
/// .behindWindow blending and .darkAqua appearance — maximising privacy contrast
/// regardless of the user's system theme.
struct BlurView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    /// Appearance override. Defaults to .darkAqua for maximum contrast.
    var appearance: NSAppearance.Name? = .darkAqua

    init(
        material: NSVisualEffectView.Material = .fullScreenUI,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
        appearance: NSAppearance.Name? = .darkAqua
    ) {
        self.material = material
        self.blendingMode = blendingMode
        self.appearance = appearance
    }

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        if let name = appearance {
            view.appearance = NSAppearance(named: name)
        }
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        if let name = appearance {
            nsView.appearance = NSAppearance(named: name)
        } else {
            nsView.appearance = nil
        }
    }
}
