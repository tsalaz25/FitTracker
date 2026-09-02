//
//  SharedFields.swift
//  FitTracker
//
//  Created by Tomas Salaz on 8/25/26.
//

import SwiftUI
import UIKit

// MARK: - Keyboard dismissal

extension View {
    /// Adds a single full-width Done bar above the keyboard.
    /// Apply this ONCE per screen, on the outermost List / Form /
    /// ScrollView — never on individual fields.
    func keyboardDoneBar() -> some View {
        modifier(KeyboardDoneBar())
    }
}

struct KeyboardDoneBar: ViewModifier {
    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .keyboard) {
                Button {
                    KeyboardDoneBar.dismiss()
                } label: {
                    Text("Done")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    static func dismiss() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
    }
}

// MARK: - Integer field (reps)

/// Whole-number entry. Empty shows "—" rather than 0, and typing "8"
/// gives 8 rather than 80.
struct RepsField: View {
    @Binding var value: Int
    var placeholder = "—"
    var width: CGFloat = 54
    var maxDigits = 3
    var alignment: TextAlignment = .center

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .keyboardType(.numberPad)
            .multilineTextAlignment(alignment)
            .frame(width: width)
            .textFieldStyle(.roundedBorder)
            .focused($focused)
            .onAppear { text = value > 0 ? String(value) : "" }
            .onChange(of: text) { _, newValue in
                let cleaned = Self.clean(newValue, maxDigits: maxDigits)
                if cleaned != newValue { text = cleaned }
                value = Int(cleaned) ?? 0
            }
            .onChange(of: value) { _, newValue in
                if !focused {
                    text = newValue > 0 ? String(newValue) : ""
                }
            }
            .onChange(of: focused) { _, isFocused in
                if !isFocused && text.isEmpty && value > 0 {
                    text = String(value)
                }
            }
    }

    /// Digits only, no leading zeros, capped length.
    static func clean(_ raw: String, maxDigits: Int) -> String {
        let digits = raw.filter(\.isNumber)
        let noLeadingZeros = String(digits.drop(while: { $0 == "0" }))
        return String(noLeadingZeros.prefix(maxDigits))
    }
}

// MARK: - Optional decimal field (weight)

/// Decimal entry that stays empty rather than showing 0.
struct WeightField: View {
    @Binding var value: Double?
    var placeholder = "—"
    var width: CGFloat = 66

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.center)
            .frame(width: width)
            .textFieldStyle(.roundedBorder)
            .focused($focused)
            .onAppear { sync() }
            .onChange(of: text) { _, newValue in
                let cleaned = Self.clean(newValue)
                if cleaned != newValue { text = cleaned }
                value = cleaned.isEmpty ? nil : Double(cleaned)
            }
            .onChange(of: value) { _, _ in
                if !focused { sync() }
            }
    }

    private func sync() {
        guard let v = value, v > 0 else { text = ""; return }
        text = v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }

    /// One decimal point, no leading zeros except "0.x", max 6 chars.
    static func clean(_ raw: String) -> String {
        var seenDot = false
        var out = ""
        for ch in raw {
            if ch.isNumber {
                out.append(ch)
            } else if (ch == "." || ch == ",") && !seenDot {
                seenDot = true
                out.append(".")
            }
        }
        while out.count > 1, out.hasPrefix("0"), !out.hasPrefix("0.") {
            out.removeFirst()
        }
        return String(out.prefix(6))
    }
}

// MARK: - Time field (mm:ss)

/// mm:ss entry with a live mask — type 830, get 8:30. Capped at 99:59.
struct TimeField: View {
    @Binding var seconds: Double?
    var placeholder = "--:--"
    var width: CGFloat = 72

    @State private var text = ""
    @FocusState private var focused: Bool

    private let maxSeconds: Double = 99 * 60 + 59

    var body: some View {
        TextField(placeholder, text: $text)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.center)
            .frame(width: width)
            .textFieldStyle(.roundedBorder)
            .focused($focused)
            .onAppear { sync() }
            .onChange(of: text) { _, newValue in
                let formatted = Self.format(newValue)
                if formatted != newValue { text = formatted }
            }
            .onChange(of: seconds) { _, _ in
                if !focused { sync() }
            }
            .onChange(of: focused) { _, isFocused in
                if !isFocused { commit() }
            }
    }

    private func sync() {
        guard let s = seconds, s > 0 else { text = ""; return }
        text = TimeFormat.mmss(min(s, maxSeconds))
    }

    private func commit() {
        let digits = text.filter(\.isNumber)
        if digits.isEmpty {
            seconds = nil
            text = ""
            return
        }
        let padded = String(repeating: "0", count: max(0, 3 - digits.count)) + digits
        let secPart = Int(padded.suffix(2)) ?? 0
        let minPart = Int(padded.dropLast(2)) ?? 0
        let total = Double(min(minPart, 99) * 60 + min(secPart, 59))
        seconds = total > 0 ? total : nil
        sync()
    }

    /// Live mask: digits become m:ss / mm:ss as you type.
    static func format(_ raw: String) -> String {
        let digits = String(raw.filter(\.isNumber).prefix(4))
        guard !digits.isEmpty else { return "" }
        if digits.count <= 2 { return digits }
        let secPart = digits.suffix(2)
        let minPart = digits.dropLast(2)
        return "\(minPart):\(secPart)"
    }
}
