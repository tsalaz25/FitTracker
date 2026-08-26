//
//  SharedFields.swift
//  FitTracker
//
//  Created by Tomas Salaz on 8/25/26.
//

import SwiftUI

/// mm:ss entry. Commits when focus leaves the field, so typing
/// "8:3" on the way to "8:30" doesn't get parsed mid-entry.
struct TimeField: View {
    @Binding var seconds: Double?
    var placeholder = "0:00"
    var width: CGFloat = 72

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .keyboardType(.numbersAndPunctuation)
            .multilineTextAlignment(.center)
            .frame(width: width)
            .textFieldStyle(.roundedBorder)
            .focused($focused)
            .onAppear { sync() }
            .onChange(of: seconds) { _, _ in
                if !focused { sync() }
            }
            .onChange(of: focused) { _, isFocused in
                if !isFocused {
                    seconds = TimeFormat.parse(text)
                    sync()
                }
            }
    }

    private func sync() {
        text = seconds.map { TimeFormat.mmss($0) } ?? ""
    }
}

/// Non-optional wrapper for plan targets, which always have a value.
struct TimeFieldRequired: View {
    @Binding var seconds: Double
    var width: CGFloat = 72

    var body: some View {
        TimeField(seconds: Binding(
            get: { seconds },
            set: { newValue in
                if let v = newValue, v > 0 { seconds = v }
            }
        ), width: width)
    }
}

struct NumberField: View {
    @Binding var value: Double?
    var placeholder: String = ""
    var width: CGFloat = 66

    var body: some View {
        TextField(placeholder, value: $value, format: .number)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.center)
            .frame(width: width)
            .textFieldStyle(.roundedBorder)
    }
}

struct IntField: View {
    @Binding var value: Int?
    var placeholder: String = ""
    var width: CGFloat = 56

    var body: some View {
        TextField(placeholder, value: $value, format: .number)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.center)
            .frame(width: width)
            .textFieldStyle(.roundedBorder)
    }
}
