import SwiftUI

/// Une touche du clavier dessiné. `code` est le code de touche du Mac (position physique) :
/// le Mac traduit lui-même selon sa disposition, comme avec un vrai clavier.
struct KeyDef: Identifiable {
    var label: String
    var shifted: String? = nil
    var code: UInt16
    var width: CGFloat = 1
    var modifier: ModifierFlags? = nil
    var action: MacAction? = nil
    var symbol: String? = nil

    var id: String { "\(code)-\(label)-\(action?.rawValue ?? 255)" }
}

private func keys(_ codes: [UInt16], _ labels: [(String, String?)]) -> [KeyDef] {
    zip(codes, labels).map { KeyDef(label: $1.0, shifted: $1.1, code: $0) }
}

private func letters(_ codes: [UInt16], _ string: String) -> [KeyDef] {
    zip(codes, string).map { KeyDef(label: String($1).uppercased(), code: $0) }
}

enum KeyboardRows {
    static let functionRow: [KeyDef] = [
        KeyDef(label: "esc", code: 53),
        KeyDef(label: "", code: 0, action: .brightnessDown, symbol: "sun.min"),
        KeyDef(label: "", code: 0, action: .brightnessUp, symbol: "sun.max"),
        KeyDef(label: "", code: 0, action: .missionControl, symbol: "rectangle.3.group"),
        KeyDef(label: "", code: 0, action: .launchpad, symbol: "square.grid.3x3"),
        KeyDef(label: "", code: 0, action: .showDesktop, symbol: "menubar.dock.rectangle"),
        KeyDef(label: "", code: 0, action: .previousTrack, symbol: "backward.fill"),
        KeyDef(label: "", code: 0, action: .playPause, symbol: "playpause.fill"),
        KeyDef(label: "", code: 0, action: .nextTrack, symbol: "forward.fill"),
        KeyDef(label: "", code: 0, action: .mute, symbol: "speaker.slash.fill"),
        KeyDef(label: "", code: 0, action: .volumeDown, symbol: "speaker.wave.1.fill"),
        KeyDef(label: "", code: 0, action: .volumeUp, symbol: "speaker.wave.3.fill"),
    ]

    static let bottomRow: [KeyDef] = [
        KeyDef(label: "control", code: 59, width: 1.2, modifier: .control),
        KeyDef(label: "option", code: 58, width: 1.2, modifier: .option),
        KeyDef(label: "⌘", code: 55, width: 1.4, modifier: .command),
        KeyDef(label: "", code: 49, width: 5),
        KeyDef(label: "⌘", code: 54, width: 1.4, modifier: .command),
        KeyDef(label: "", code: 123, width: 0.9, symbol: "arrowtriangle.left.fill"),
        KeyDef(label: "", code: 125, width: 0.9, symbol: "arrowtriangle.down.fill"),
        KeyDef(label: "", code: 126, width: 0.9, symbol: "arrowtriangle.up.fill"),
        KeyDef(label: "", code: 124, width: 0.9, symbol: "arrowtriangle.right.fill"),
    ]

    private static let numberCodes: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25, 29, 27, 24]
    private static let topCodes: [UInt16] = [12, 13, 14, 15, 17, 16, 32, 34, 31, 35, 33, 30]
    private static let homeCodes: [UInt16] = [0, 1, 2, 3, 5, 4, 38, 40, 37, 41, 39, 42]
    private static let bottomCodes: [UInt16] = [6, 7, 8, 9, 11, 45, 46, 43, 47, 44]

    private static let delete = KeyDef(label: "", code: 51, width: 1.5, symbol: "delete.left")
    private static let tab = KeyDef(label: "", code: 48, width: 1.5, symbol: "arrow.right.to.line")
    private static let enter = KeyDef(label: "", code: 36, width: 1.5, symbol: "return")

    // Rangées construites pas à pas : une seule longue expression ralentit beaucoup la compilation.
    static func rows(_ layout: KeyboardLayout) -> [[KeyDef]] {
        layout == .azerty ? azerty : qwerty
    }

    private static let azerty: [[KeyDef]] = {
        let shift = KeyDef(label: "", code: 56, width: 1.25, modifier: .shift, symbol: "shift")
        let numberLabels: [(String, String?)] = [("&", "1"), ("é", "2"), ("\"", "3"), ("'", "4"), ("(", "5"), ("§", "6"),
                                                 ("è", "7"), ("!", "8"), ("ç", "9"), ("à", "0"), (")", "°"), ("-", "_")]
        var r1: [KeyDef] = [KeyDef(label: "@", shifted: "#", code: 10)]
        r1 += keys(numberCodes, numberLabels)
        r1.append(delete)

        var r2: [KeyDef] = [tab]
        r2 += letters(Array(topCodes.prefix(10)), "azertyuiop")
        r2 += keys(Array(topCodes.suffix(2)), [("^", "¨"), ("$", "*")])

        var r3: [KeyDef] = letters(Array(homeCodes.prefix(10)), "qsdfghjklm")
        r3 += keys(Array(homeCodes.suffix(2)), [("ù", "%"), ("`", "£")])
        r3.append(enter)

        var r4: [KeyDef] = [shift, KeyDef(label: "<", shifted: ">", code: 50)]
        r4 += letters(Array(bottomCodes.prefix(6)), "wxcvbn")
        r4 += keys(Array(bottomCodes.suffix(4)), [(",", "?"), (";", "."), (":", "/"), ("=", "+")])
        r4.append(shift)
        return [r1, r2, r3, r4]
    }()

    private static let qwerty: [[KeyDef]] = {
        let shift = KeyDef(label: "", code: 56, width: 1.75, modifier: .shift, symbol: "shift")
        let numberLabels: [(String, String?)] = [("1", "!"), ("2", "@"), ("3", "#"), ("4", "$"), ("5", "%"), ("6", "^"),
                                                 ("7", "&"), ("8", "*"), ("9", "("), ("0", ")"), ("-", "_"), ("=", "+")]
        var r1: [KeyDef] = [KeyDef(label: "`", shifted: "~", code: 50)]
        r1 += keys(numberCodes, numberLabels)
        r1.append(delete)

        var r2: [KeyDef] = [tab]
        r2 += letters(Array(topCodes.prefix(10)), "qwertyuiop")
        r2 += keys(Array(topCodes.suffix(2)), [("[", "{"), ("]", "}")])

        var r3: [KeyDef] = letters(Array(homeCodes.prefix(9)), "asdfghjkl")
        r3 += keys(Array(homeCodes.suffix(3)), [(";", ":"), ("'", "\""), ("\\", "|")])
        r3.append(enter)

        var r4: [KeyDef] = [shift]
        r4 += letters(Array(bottomCodes.prefix(7)), "zxcvbnm")
        r4 += keys(Array(bottomCodes.suffix(3)), [(",", "<"), (".", ">"), ("/", "?")])
        r4.append(shift)
        return [r1, r2, r3, r4]
    }()
}

/// Clavier de MacBook dessiné. Les touches de modification (⇧ control option ⌘)
/// s'allument d'un toucher et s'appliquent à la touche suivante.
struct KeyboardView: View {
    let session: MacSession
    let layout: KeyboardLayout
    let theme: Theme

    @State private var modifiers: ModifierFlags = []

    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 4
            let rows = KeyboardRows.rows(layout)
            let rowHeight = (geo.size.height - spacing * 6) / 6.6
            VStack(spacing: spacing) {
                row(KeyboardRows.functionRow, width: geo.size.width, spacing: spacing)
                    .frame(height: rowHeight * 0.6)
                ForEach(rows.indices, id: \.self) { i in
                    row(rows[i], width: geo.size.width, spacing: spacing)
                        .frame(height: rowHeight)
                }
                row(KeyboardRows.bottomRow, width: geo.size.width, spacing: spacing)
                    .frame(height: rowHeight)
            }
        }
    }

    private func row(_ keys: [KeyDef], width: CGFloat, spacing: CGFloat) -> some View {
        let units = keys.reduce(0) { $0 + $1.width }
        let unit = (width - spacing * CGFloat(keys.count - 1)) / units
        return HStack(spacing: spacing) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                KeyCap(key: key,
                       shift: modifiers.contains(.shift),
                       active: key.modifier.map { modifiers.contains($0) } ?? false,
                       theme: theme,
                       onDown: { press(key) },
                       onUp: { release(key) })
                    .frame(width: unit * key.width)
            }
        }
    }

    private func press(_ key: KeyDef) {
        Feedback.key()
        if key.modifier != nil || key.action != nil { return }
        session.key(key.code, down: true, flags: modifiers)
    }

    private func release(_ key: KeyDef) {
        if let modifier = key.modifier {
            if modifiers.contains(modifier) {
                modifiers.remove(modifier)
            } else {
                modifiers.insert(modifier)
            }
            return
        }
        if let action = key.action {
            session.perform(action)
            return
        }
        session.key(key.code, down: false, flags: modifiers)
        modifiers = []
    }
}

private struct KeyCap: View {
    let key: KeyDef
    let shift: Bool
    let active: Bool
    let theme: Theme
    let onDown: () -> Void
    let onUp: () -> Void

    @State private var pressed = false

    var body: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(active ? theme.keyActive : (pressed ? theme.keyPressed : theme.key))
            .shadow(color: .black.opacity(0.25), radius: 0.5, y: 1)
            .overlay(label)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !pressed {
                            pressed = true
                            onDown()
                        }
                    }
                    .onEnded { _ in
                        pressed = false
                        onUp()
                    }
            )
    }

    @ViewBuilder private var label: some View {
        if let symbol = key.symbol {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.keyText)
        } else if let shifted = key.shifted {
            VStack(spacing: 0) {
                Text(shifted).opacity(shift ? 1 : 0.6)
                Text(key.label).opacity(shift ? 0.6 : 1)
            }
            .font(.system(size: 10))
            .foregroundStyle(theme.keyText)
        } else {
            Text(key.label)
                .font(.system(size: key.label.count > 1 ? 9 : 14))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .foregroundStyle(theme.keyText)
        }
    }
}
