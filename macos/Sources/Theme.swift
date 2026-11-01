import AppKit
import SwiftUI

/// xav.ie's palette and surfaces (xav-ie.github.io src/styles/global.css), for light and dark mode.
struct Palette {
    let background, foreground, alt: Color
    let surfaceTop, surfaceBottom, shadow, highlight: Color
    /// A brighter purple for "on" switch tracks.
    let onTrack: Color
    /// The off switch trough: a little brighter than the card so it reads against it.
    let offTrack: Color
    /// The switch knob; in dark mode a purple-grey, so it stands out against both troughs.
    let knobTop, knobBottom: Color

    static func current(_ scheme: ColorScheme) -> Palette {
        // --background / --foreground / --alt, with the color-mix() derived tones precomputed.
        scheme == .dark
            ? Palette(background: rgb(0x12081A), foreground: rgb(0xFFF17B), alt: rgb(0x51D136),
                      surfaceTop: rgb(0x210F2E), surfaceBottom: rgb(0x110718),
                      shadow: rgb(0x100717), highlight: rgb(0x413948), onTrack: rgb(0x4A2A63), offTrack: rgb(0x24132F),
                      knobTop: rgb(0x5A5066), knobBottom: rgb(0x3A3344))
            : Palette(background: rgb(0xBEBDB6), foreground: rgb(0x281336), alt: rgb(0x257015),
                      surfaceTop: rgb(0xC3C2BC), surfaceBottom: rgb(0xB3B2AB),
                      shadow: rgb(0xA7A6A0), highlight: rgb(0xCBCAC5), onTrack: rgb(0x9E8AAF), offTrack: rgb(0xA9A8A1),
                      knobTop: rgb(0xC3C2BC), knobBottom: rgb(0xB3B2AB))
    }

    private static func rgb(_ hex: Int) -> Color {
        Color(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// The site's faint fractal-noise overlay: white specks at ~2% opacity, generated once.
let noise: NSImage = {
    let size = 240
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    var rng = SystemRandomNumberGenerator()
    for y in 0..<size {
        for x in 0..<size {
            let a = CGFloat(UInt8.random(in: 0...255, using: &rng)) / 255 * 0.05
            rep.setColor(NSColor(white: 1, alpha: a), atX: x, y: y)
        }
    }
    let image = NSImage(size: NSSize(width: size, height: size))
    image.addRepresentation(rep)
    return image
}()

extension View {
    /// The site's "bubble" surface: noise over a 155° gradient, soft corner shadow, inset rim.
    func bubble(_ palette: Palette, radius: CGFloat = 18) -> some View {
        background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(LinearGradient(colors: [palette.surfaceTop, palette.surfaceBottom],
                                     startPoint: UnitPoint(x: 0.21, y: 0.05), endPoint: UnitPoint(x: 0.79, y: 0.95)))
                .overlay(Image(nsImage: noise).resizable(resizingMode: .tile).clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous)))
                // Inset bevel: a light top-left edge fading out, like the site's inset highlight.
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.14), .clear],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                )
                // One soft drop shadow down-right; the site's own shadow tone vanishes on #12081a.
                .compositingGroup()
                .shadow(color: Color.black.opacity(0.45), radius: 10, x: 4, y: 6)
                .accessibilityHidden(true)
        )
    }
}

/// A full-width card with a serif heading, like the site's project cards.
struct Card<Content: View>: View {
    let palette: Palette
    var title: String?
    /// VoiceOver name for a card without a visible title.
    var label: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title { Text(title).font(.custom("Palatino", size: 17).weight(.semibold)).accessibilityAddTraits(.isHeader) }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .bubble(palette)
        // One VoiceOver group per card: skim the sections, interact with one to reach its controls.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title ?? label ?? "")
    }
}

/// App-level keyboard navigation. macOS only lets Tab reach text fields unless the user enables
/// Keyboard navigation, so the window drives focus itself: controls register their on-screen frame
/// and action, Tab/Shift-Tab walk them in reading order, Space/Return activate, Escape clears.
final class KeyboardFocus: ObservableObject {
    struct Entry {
        var frame: CGRect
        var action: () -> Void
        /// A text field: it takes real keyboard focus while current, instead of the window.
        var editsText = false
    }

    @Published var current: UUID?
    var entries: [UUID: Entry] = [:]

    private var ordered: [UUID] {
        entries.sorted { a, b in
            abs(a.value.frame.midY - b.value.frame.midY) < 6 ? a.value.frame.minX < b.value.frame.minX : a.value.frame.midY < b.value.frame.midY
        }.map(\.key)
    }

    func move(by step: Int) {
        let order = ordered
        guard !order.isEmpty else { return }
        if let current, let i = order.firstIndex(of: current) {
            self.current = order[(i + step + order.count) % order.count]
        } else {
            current = step > 0 ? order.first : order.last
        }
    }

    func activate() -> Bool {
        guard let current, let entry = entries[current] else { return false }
        entry.action()
        return true
    }
}

extension View {
    /// Joins the window's keyboard navigation; draws the site's `:focus-visible` ring (a 2pt
    /// foreground outline 2pt outside the control) while focused.
    func keyboardFocusable(_ palette: Palette, radius: CGFloat = 8, action: @escaping () -> Void) -> some View {
        modifier(KeyboardFocusable(palette: palette, radius: radius, action: action))
    }

    /// The window side: owns key handling for everything marked `keyboardFocusable`.
    func keyboardNavigation(_ focus: KeyboardFocus) -> some View {
        modifier(KeyboardNavigation(focus: focus))
    }

    /// `onChange(of:)` with the new value on every macOS version: the two-value form is macOS 14+, and
    /// the `perform:` form it replaces is deprecated there.
    @ViewBuilder func onChangeCompat<V: Equatable>(of value: V, perform action: @escaping (V) -> Void) -> some View {
        if #available(macOS 14, *) {
            onChange(of: value) { _, new in action(new) }
        } else {
            onChange(of: value, perform: action)
        }
    }

    /// Key handling for macOS 12–13, which lack `onKeyPress`: `handle` sees the app's key-down events
    /// while this view is on screen and returns true to swallow one.
    func keyDownMonitor(_ handle: @escaping (NSEvent) -> Bool) -> some View {
        modifier(KeyDownMonitor(handle: handle))
    }
}

private final class KeyDownHandler {
    var handle: (NSEvent) -> Bool = { _ in false }
    var monitor: Any?
}

private struct KeyDownMonitor: ViewModifier {
    let handle: (NSEvent) -> Bool
    @State private var handler = KeyDownHandler()

    func body(content: Content) -> some View {
        // Refresh on every render, like KeyboardFocusable's action: the closure reads the current state.
        handler.handle = handle
        return content
            .onAppear {
                guard handler.monitor == nil else { return }
                handler.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [handler] event in
                    handler.handle(event) ? nil : event
                }
            }
            .onDisappear {
                if let monitor = handler.monitor { NSEvent.removeMonitor(monitor) }
                handler.monitor = nil
            }
    }
}

extension Animation {
    /// The switches' knob: `.snappy` on macOS 14+, the same small-bounce spring before it.
    static var switchKnob: Animation {
        if #available(macOS 14, *) { return .snappy(duration: 0.18) }
        return .spring(response: 0.18, dampingFraction: 0.85)
    }
}

/// A switch's sunken trough: an inner shadow down-right and a highlight along the top-left edge.
private struct Trough: View {
    let color: Color
    let palette: Palette

    var body: some View {
        if #available(macOS 13, *) {
            Capsule()
                .fill(color
                    .shadow(.inner(color: .black.opacity(0.45), radius: 4, x: 3, y: 3))
                    .shadow(.inner(color: palette.highlight, radius: 1.5, x: -1, y: -1)))
        } else {
            // Inner shadows (macOS 13+) approximated: blurred rims, offset and clipped to the capsule.
            Capsule()
                .fill(color)
                .overlay(Capsule().stroke(Color.black.opacity(0.45), lineWidth: 8).blur(radius: 4).offset(x: 3, y: 3))
                .overlay(Capsule().stroke(palette.highlight, lineWidth: 3).blur(radius: 1.5).offset(x: -1, y: -1))
                .clipShape(Capsule())
        }
    }
}

private struct KeyboardFocusable: ViewModifier {
    let palette: Palette
    let radius: CGFloat
    let action: () -> Void
    @EnvironmentObject private var focus: KeyboardFocus
    @State private var id = UUID()

    func body(content: Content) -> some View {
        // Refresh the stored action on every render: it closes over the current state (e.g. whether
        // the hotspot is on), and a stale copy would repeat the first action on later key presses.
        focus.entries[id]?.action = action
        return content
            .background(GeometryReader { geometry in
                let frame = geometry.frame(in: .named(KeyboardNavigation.space))
                Color.clear
                    .onAppear { focus.entries[id] = .init(frame: frame, action: action) }
                    .onChangeCompat(of: frame) { frame in focus.entries[id] = .init(frame: frame, action: action) }
            })
            .onDisappear {
                focus.entries[id] = nil
                if focus.current == id { focus.current = nil }
            }
            .overlay(
                RoundedRectangle(cornerRadius: radius + 4, style: .continuous)
                    .stroke(palette.foreground, lineWidth: 2)
                    .padding(-4)
                    .opacity(focus.current == id ? 1 : 0)
                    .allowsHitTesting(false)
            )
    }
}

private struct KeyboardNavigation: ViewModifier {
    static let space = "keyboard-navigation"
    static let repeatInterval: TimeInterval = 0.1
    @ObservedObject var focus: KeyboardFocus
    @State private var lastMove = Date.distantPast
    @FocusState private var windowFocused: Bool

    @ViewBuilder func body(content: Content) -> some View {
        let base = content
            .coordinateSpace(name: Self.space)
            .environmentObject(focus)
        if #available(macOS 14, *) {
            base
                .focusable()
                .focusEffectDisabled()
                .focused($windowFocused)
                .onAppear { windowFocused = true }
                // Hand key focus back to the window whenever the current item isn't a text field.
                .onChange(of: focus.current) { _, current in
                    if current.flatMap({ focus.entries[$0]?.editsText }) != true { windowFocused = true }
                }
                // macOS delivers Shift-Tab as its own back-tab character (U+0019), not as Tab with Shift.
                .onKeyPress(keys: [.tab, KeyEquivalent("\u{19}")], phases: [.down, .repeat]) { press in
                    // Holding Tab repeats at the system key-repeat rate; cap it so focus stays followable.
                    if press.phase == .repeat, Date().timeIntervalSince(lastMove) < Self.repeatInterval { return .handled }
                    lastMove = Date()
                    let back = press.key == KeyEquivalent("\u{19}") || press.modifiers.contains(.shift)
                    focus.move(by: back ? -1 : 1)
                    return .handled
                }
                .onKeyPress(keys: [.space, .return]) { _ in focus.activate() ? .handled : .ignored }
                .onKeyPress(.escape) {
                    focus.current = nil
                    return .handled
                }
        } else {
            base
                // Best effort: macOS 12–13 may give the first text field key focus as the window opens;
                // start with nothing focused, as above.
                .onAppear {
                    DispatchQueue.main.async {
                        NSApp.keyWindow?.makeFirstResponder(nil)
                        focus.current = nil
                    }
                }
                .keyDownMonitor(handleKeyDown)
        }
    }

    /// macOS 12–13: the same keys from a key-down monitor. A text field being edited keeps its keys.
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.isDisjoint(with: [.command, .control, .option]),
              !(NSApp.keyWindow?.firstResponder is NSText) else { return false }
        let key = event.charactersIgnoringModifiers ?? ""
        switch key {
        case "\t", "\u{19}":
            if event.isARepeat, Date().timeIntervalSince(lastMove) < Self.repeatInterval { return true }
            lastMove = Date()
            focus.move(by: key == "\u{19}" || event.modifierFlags.contains(.shift) ? -1 : 1)
            return true
        case " ", "\r":
            return focus.activate()
        case "\u{1b}":
            focus.current = nil
            return true
        default:
            return false
        }
    }
}

/// The site's theme-toggle look as an on/off switch: a sunken trough with a raised knob that is dim
/// on the left when off and lit in the foreground colour on the right when on. Label on the left.
struct TrailingSwitchStyle: ToggleStyle {
    let palette: Palette

    func makeBody(configuration: Configuration) -> some View { SwitchRow(configuration: configuration, palette: palette) }
}

private struct SwitchRow: View {
    let configuration: ToggleStyleConfiguration
    let palette: Palette
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        HStack {
            configuration.label
            Spacer()
            Button(action: toggle) {
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    // Sunken trough; a brighter purple when on.
                    Trough(color: configuration.isOn ? palette.onTrack : palette.offTrack, palette: palette)
                        .frame(width: 46, height: 26)
                    // Raised purple knob with a pronounced light top-left rim and dark bottom-right edge.
                    Circle()
                        .fill(LinearGradient(colors: [palette.knobTop, palette.knobBottom],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .overlay(Circle().strokeBorder(
                            LinearGradient(colors: [Color.white.opacity(0.6), .clear, Color.black.opacity(0.6)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: 1.6))
                        .shadow(color: .black.opacity(0.6), radius: 2.5, x: 1.5, y: 2)
                        .frame(width: 20, height: 20)
                        .padding(3)
                }
            }
            .buttonStyle(.plain)
            .keyboardFocusable(palette, radius: 13, action: toggle)
            .opacity(enabled ? 1 : 0.4)
        }
        // VoiceOver sees a native switch with the row's label and on/off value.
        .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
    }

    private func toggle() {
        guard enabled else { return }
        withAnimation(.switchKnob) { configuration.isOn.toggle() }
    }
}

/// A link in the site's style: accent colour, underlined on hover, pointing-hand cursor, focus ring.
struct SiteLink<Icon: View>: View {
    let title: String
    let url: URL
    let palette: Palette
    @ViewBuilder var icon: Icon
    @State private var hovering = false

    var body: some View {
        Link(destination: url) {
            Label { Text(title).underline(hovering) } icon: { icon }
        }
        .foregroundStyle(palette.alt)
        .onHover { inside in
            hovering = inside
            inside ? NSCursor.pointingHand.push() : NSCursor.pop()
        }
        .keyboardFocusable(palette, radius: 4) { NSWorkspace.shared.open(url) }
    }
}

extension SiteLink where Icon == EmptyView {
    init(_ title: String, url: URL, palette: Palette) {
        self.init(title: title, url: url, palette: palette) { EmptyView() }
    }
}

/// Plain text buttons in the accent colour, underlined on hover (Show, Copy).
struct TextButtonStyle: ButtonStyle {
    let palette: Palette

    func makeBody(configuration: Configuration) -> some View { TextButtonLabel(configuration: configuration, palette: palette) }
}

private struct TextButtonLabel: View {
    let configuration: ButtonStyleConfiguration
    let palette: Palette
    @State private var hovering = false

    var body: some View {
        underlinedLabel
            .opacity(configuration.isPressed ? 0.6 : 1)
            .onHover { hovering = $0 }
    }

    /// View-level `underline` is macOS 13+; before it, a 1pt rule under the label stands in.
    @ViewBuilder private var underlinedLabel: some View {
        if #available(macOS 13, *) {
            configuration.label
                .foregroundStyle(palette.alt)
                .underline(hovering)
        } else {
            configuration.label
                .foregroundStyle(palette.alt)
                .overlay(alignment: .bottom) { Rectangle().frame(height: 1).opacity(hovering ? 1 : 0) }
        }
    }
}

/// The window body: the site background and noise in a rounded shape, with a skeuomorphic rim — a
/// light inner edge along the top-left fading to a dark one at the bottom-right.
struct WindowSurface: View {
    static let radius: CGFloat = 24
    let palette: Palette

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
        shape
            .fill(palette.background)
            .overlay(Image(nsImage: noise).resizable(resizingMode: .tile).clipShape(shape))
            .overlay(shape.strokeBorder(
                LinearGradient(colors: [Color.white.opacity(0.22), Color.white.opacity(0.04), Color.black.opacity(0.55)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: 1.5))
            .overlay(shape.inset(by: 1.5).strokeBorder(Color.black.opacity(0.25), lineWidth: 1))
            .accessibilityHidden(true)
    }
}

/// The hotspot switch: like the others, but with a third, unknown state — knob centred and disabled
/// until the phone has reported a state it can actually change.
struct HotspotSwitch: View {
    /// nil while the hotspot's state isn't known yet.
    let isOn: Bool?
    let enabled: Bool
    let palette: Palette
    let set: (Bool) -> Void

    var body: some View {
        HStack {
            Text("Hotspot")
            Spacer()
            Button(action: flip) {
                ZStack(alignment: isOn == true ? .trailing : isOn == false ? .leading : .center) {
                    Trough(color: isOn == true ? palette.onTrack : palette.offTrack, palette: palette)
                        .frame(width: 46, height: 26)
                    Circle()
                        .fill(LinearGradient(colors: [palette.knobTop, palette.knobBottom],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .overlay(Circle().strokeBorder(
                            LinearGradient(colors: [Color.white.opacity(0.6), .clear, Color.black.opacity(0.6)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: 1.6))
                        .shadow(color: .black.opacity(0.6), radius: 2.5, x: 1.5, y: 2)
                        .frame(width: 20, height: 20)
                        .padding(3)
                }
                .animation(.switchKnob, value: isOn)
            }
            .buttonStyle(.plain)
            .disabled(!enabled)
            .keyboardFocusable(palette, radius: 13, action: flip)
            .opacity(enabled ? 1 : 0.4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hotspot")
        .accessibilityValue(isOn == nil ? "unknown" : isOn! ? "on" : "off")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { flip() }
    }

    private func flip() {
        guard enabled, let isOn else { return }
        set(!isOn)
    }
}

/// Makes the view it backs a handle for moving the window (the window itself isn't draggable by its
/// background, so only the header moves it).
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragView: NSView {
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }
}

/// Replaces the hidden traffic lights: round bubble buttons for minimise and close.
struct WindowControls: View {
    let palette: Palette

    var body: some View {
        HStack(spacing: 10) {
            control("minus", "Minimize") { NSApp.keyWindow?.miniaturize(nil) }
            control("xmark", "Close") { NSApp.keyWindow?.performClose(nil) }
        }
        // Duplicates of Window → Minimize/Close (⌘M/⌘W), so VoiceOver skips them.
        .accessibilityHidden(true)
    }

    private func control(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        WindowControl(symbol: symbol, help: help, palette: palette, action: action)
    }
}

private struct WindowControl: View {
    let symbol: String
    let help: String
    let palette: Palette
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 10, weight: .bold)).frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .foregroundStyle(palette.foreground)
        .opacity(hovering ? 1 : 0.7)
        .bubble(palette, radius: 13)
        .onHover { hovering = $0 }
        .keyboardFocusable(palette, radius: 13, action: action)
        .help(help)
        .background(GeometryReader { geometry in
            let frame = geometry.frame(in: .global)
            Color.clear
                .onAppear { WindowButton.frames[help] = frame }
                .onChangeCompat(of: frame) { frame in WindowButton.frames[help] = frame }
        })
    }
}

/// A labelled whole number of seconds, typed into a small field. It joins the window's Tab order;
/// out-of-range values are clamped when the edit is committed (Return, Tab or leaving the field).
struct SecondsField: View {
    let title: String
    @Binding var seconds: Int
    let range: ClosedRange<Int>
    let palette: Palette
    @EnvironmentObject private var focus: KeyboardFocus
    @State private var id = UUID()
    @State private var draft = 0
    @FocusState private var editing: Bool

    private func commit() {
        seconds = min(max(draft, range.lowerBound), range.upperBound)
        draft = seconds
    }

    private func register(_ frame: CGRect) {
        focus.entries[id] = .init(frame: frame, action: { editing = true }, editsText: true)
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
            TextField(title, value: $draft, format: .number)
                .textFieldStyle(.plain)
                .font(.system(.body, design: .monospaced))
                .multilineTextAlignment(.trailing)
                .frame(width: 48)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .bubble(palette, radius: 10)
                .labelsHidden()
                .accessibilityLabel(title)
                .focused($editing)
                .onSubmit(commit)
                .modifier(TextFieldKeys(editing: editing, tab: { back in
                    commit()
                    focus.move(by: back ? -1 : 1)
                }, escape: {
                    draft = seconds
                    focus.current = nil
                }))
                .background(GeometryReader { geometry in
                    let frame = geometry.frame(in: .named(KeyboardNavigation.space))
                    Color.clear
                        .onAppear { register(frame) }
                        .onChangeCompat(of: frame) { frame in register(frame) }
                })
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(palette.foreground, lineWidth: 2)
                        .padding(-4)
                        .opacity(focus.current == id ? 1 : 0)
                        .allowsHitTesting(false)
                )
            Text("sec").opacity(0.7)
            Spacer()
        }
        .onAppear { draft = seconds }
        .onDisappear {
            focus.entries[id] = nil
            if focus.current == id { focus.current = nil }
        }
        .onChangeCompat(of: focus.current) { current in editing = current == id }
        .onChangeCompat(of: editing) { now in
            if now { focus.current = id } else { commit() }
        }
    }
}

/// Tab/Shift-Tab and Escape for a text field: `onKeyPress` on macOS 14+, a key-down monitor that acts
/// only while the field is being edited before it.
private struct TextFieldKeys: ViewModifier {
    let editing: Bool
    let tab: (_ back: Bool) -> Void
    let escape: () -> Void

    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 14, *) {
            content
                .onKeyPress(keys: [.tab, KeyEquivalent("\u{19}")]) { press in
                    tab(press.key == KeyEquivalent("\u{19}") || press.modifiers.contains(.shift))
                    return .handled
                }
                .onKeyPress(.escape) {
                    escape()
                    return .handled
                }
        } else {
            content.keyDownMonitor { event in
                guard editing, event.modifierFlags.isDisjoint(with: [.command, .control, .option]) else { return false }
                let key = event.charactersIgnoringModifiers ?? ""
                switch key {
                case "\t", "\u{19}":
                    tab(key == "\u{19}" || event.modifierFlags.contains(.shift))
                    return true
                case "\u{1b}":
                    escape()
                    return true
                default:
                    return false
                }
            }
        }
    }
}
