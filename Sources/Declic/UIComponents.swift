import AppKit
import SwiftUI

// MARK: - Fonds

/// Flou de fond façon HUD macOS, toujours actif (même dans un panneau non activé).
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}

/// Zone qui permet de déplacer la fenêtre (barre d'outils dans la barre de titre).
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
    }
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

extension View {
    /// Les panneaux flottants ne sont jamais « clé » : on force l'apparence active des contrôles.
    func activeControls() -> some View {
        environment(\.controlActiveState, .key)
    }
}

/// Enfoncement au clic, avec un petit rebond au relâchement.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .brightness(configuration.isPressed ? -0.1 : 0)
            .animation(configuration.isPressed
                       ? .easeOut(duration: 0.08)
                       : .spring(response: 0.3, dampingFraction: 0.5),
                       value: configuration.isPressed)
    }
}

// MARK: - Confirmation

/// Pastille « ✓ Copié » qui apparaît en bas de l'écran pour confirmer une action.
@MainActor
enum FeedbackHUD {
    private static var panel: FloatingPanel?

    static func show(_ text: String, symbol: String = "checkmark") {
        panel?.orderOut(nil)
        Sound.success()
        let host = NSHostingView(rootView: FeedbackPill(text: text, symbol: symbol))
        let size = host.fittingSize
        host.frame = CGRect(origin: .zero, size: size)
        let p = FloatingPanel(size: size)
        p.level = .aboveOverlay
        p.ignoresMouseEvents = true
        p.contentView = host
        let vf = NSScreen.underMouse.visibleFrame
        p.setFrameOrigin(CGPoint(x: vf.midX - size.width / 2, y: vf.minY + 90))
        p.orderFrontRegardless()
        panel = p
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            guard panel === p else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.25
                p.animator().alphaValue = 0
            }, completionHandler: {
                MainActor.assumeIsolated {
                    p.orderOut(nil)
                    if panel === p { panel = nil }
                }
            })
        }
    }
}

private struct FeedbackPill: View {
    let text: String
    let symbol: String
    @State private var appeared = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.green))
                .scaleEffect(appeared ? 1 : 0.2)
            Text(text)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
        }
        .padding(.leading, 8)
        .padding(.trailing, 18)
        .frame(height: 42)
        .background(GlassFill(shape: Capsule()))
        .environment(\.colorScheme, .dark)
        .scaleEffect(appeared ? 1 : 0.7)
        .opacity(appeared ? 1 : 0)
        .padding(14)
        .onAppear {
            withAnimation(.spring(response: 0.36, dampingFraction: 0.6)) { appeared = true }
        }
    }
}

/// Matière « verre » commune aux boutons flottants.
struct GlassFill<S: InsettableShape>: View {
    let shape: S
    var prominent = false
    var tint: Color = .accentColor
    var hover = false

    var body: some View {
        ZStack {
            if prominent {
                shape.fill(tint)
                shape.fill(LinearGradient(colors: [Color.white.opacity(hover ? 0.22 : 0.14), Color.clear],
                                          startPoint: .top, endPoint: .bottom))
            } else {
                VisualEffectBackground(material: .hudWindow)
                    .clipShape(shape)
                shape.fill(Color.white.opacity(hover ? 0.2 : 0.1))
            }
            shape.strokeBorder(Color.white.opacity(prominent ? 0.28 : 0.22), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.28), radius: 6, x: 0, y: 2)
    }
}

// MARK: - Boutons

/// Grand bouton « pilule » (Copier / Enregistrer sur les vignettes, actions des HUD).
struct PillButton: View {
    let title: String
    let symbol: String
    var prominent = false
    var tint: Color = .accentColor
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 18)
            .frame(minWidth: 132)
            .frame(height: 38)
            .background(GlassFill(shape: Capsule(), prominent: prominent, tint: tint, hover: hover))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
    }
}

/// Bouton rond (icône seule).
struct CircleIconButton: View {
    let symbol: String
    let help: String
    var size: CGFloat = 30
    var dark = false
    /// Bouton « activé » (ex. vignette épinglée) : rempli de la couleur d'accent.
    var active = false
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: size, height: size)
                .background(GlassFill(shape: Circle(), prominent: active, hover: hover))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
        .help(help)
    }
}

/// Bouton icône de HUD (même style que les boutons ronds).
struct HUDIconButton: View {
    let symbol: String
    let help: String
    var tint: Color = .white
    var background: Color = .clear
    var size: CGFloat = 32
    let action: () -> Void

    var body: some View {
        CircleIconButton(symbol: symbol, help: help, size: size, action: action)
    }
}

/// Bouton principal de HUD (Enregistrer, Terminer, Arrêter…).
struct HUDTextButton: View {
    let title: String
    var symbol: String?
    var color: Color = .accentColor
    var enabled = true
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 12, weight: .bold))
                }
                Text(title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
            }
            .foregroundColor(.white.opacity(enabled ? 1 : 0.45))
            .padding(.horizontal, 18)
            .frame(height: 36)
            .background(GlassFill(shape: Capsule(), prominent: enabled, tint: color, hover: hover && enabled))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
    }
}

/// Contrôle segmenté « verre » pour les HUD (modes, formats).
struct GlassSegmented<Value: Hashable>: View {
    struct Item {
        let value: Value
        let title: String
        var symbol: String?
    }

    let items: [Item]
    let selection: Value
    let onSelect: (Value) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items.indices, id: \.self) { index in
                let item = items[index]
                let selected = item.value == selection
                Button { onSelect(item.value) } label: {
                    HStack(spacing: 6) {
                        if let symbol = item.symbol {
                            Image(systemName: symbol).font(.system(size: 13, weight: .medium))
                        }
                        Text(item.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    }
                    .foregroundColor(selected ? .black : .white.opacity(0.85))
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background(Capsule().fill(selected ? Color.white : Color.clear))
                    .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle())
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.white.opacity(0.1)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5))
        .animation(.easeOut(duration: 0.15), value: selection)
    }
}

// MARK: - HUD

/// Fond commun des HUD (barres d'enregistrement, de capture défilante…).
struct HUDBackground: ViewModifier {
    var cornerRadius: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .background(
                VisualEffectBackground(material: .hudWindow)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.35), radius: 14, x: 0, y: 5)
            .environment(\.colorScheme, .dark)
            .activeControls()
    }
}

extension View {
    func hudBackground(cornerRadius: CGFloat = 16) -> some View {
        modifier(HUDBackground(cornerRadius: cornerRadius))
    }
}

/// Point rouge qui pulse pendant un enregistrement.
struct PulsingDot: View {
    @State private var on = false

    var body: some View {
        Circle()
            .fill(Color.red)
            .frame(width: 10, height: 10)
            .opacity(on ? 1 : 0.35)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { on = true }
            }
    }
}

/// Séparateur vertical fin pour les HUD.
struct HUDDivider: View {
    var height: CGFloat = 26
    var body: some View {
        Rectangle().fill(Color.white.opacity(0.14)).frame(width: 1, height: height)
    }
}
