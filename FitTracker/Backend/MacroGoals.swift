//
//  MacroGoals.swift
//  FitTracker
//
//  Created by Tomas Salaz on 8/27/26.
//

import SwiftUI
import SwiftData

// MARK: - Model

@Model
final class MacroGoal {
    var weekday: Int = 1          // 1 = Sunday ... 7 = Saturday
    var carbs: Double = 0         // grams
    var protein: Double = 0       // grams
    var fat: Double = 0           // grams

    init(weekday: Int, carbs: Double = 0, protein: Double = 0, fat: Double = 0) {
        self.weekday = weekday
        self.carbs = carbs
        self.protein = protein
        self.fat = fat
    }

    /// Derived, never entered.
    var calories: Double {
        (carbs + protein) * 4 + fat * 9
    }

    var isSet: Bool { carbs > 0 || protein > 0 || fat > 0 }

    /// Share of calories from each macro, for the split readout.
    var split: (carbs: Double, protein: Double, fat: Double) {
        let total = calories
        guard total > 0 else { return (0, 0, 0) }
        return (carbs * 4 / total,
                protein * 4 / total,
                fat * 9 / total)
    }

    var summary: String {
        isSet
            ? "\(Int(calories)) kcal · \(Int(carbs))C \(Int(protein))P \(Int(fat))F"
            : "Not set"
    }
}

// MARK: - Lookup helper

enum Goals {
    /// Seeds the seven days once, on first launch.
    static func seedIfNeeded(_ existing: [MacroGoal], context: ModelContext) {
        guard existing.isEmpty else { return }
        for wd in 1...7 {
            context.insert(MacroGoal(weekday: wd))
        }
    }

    /// The goal that applies to a given calendar date.
    static func goal(for date: Date, in goals: [MacroGoal]) -> MacroGoal? {
        let wd = Calendar.current.component(.weekday, from: date)
        return goals.first { $0.weekday == wd }
    }
}

// MARK: - Week list

struct GoalsEditorView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \MacroGoal.weekday) private var goals: [MacroGoal]

    var body: some View {
        List {
            Section {
                ForEach(goals) { g in
                    NavigationLink {
                        GoalDayEditor(goal: g)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(PlanWeekView.names[g.weekday])
                                    .font(.headline)
                                Text(g.summary)
                                    .font(.caption)
                                    .foregroundStyle(g.isSet ? .secondary : .tertiary)
                            }
                            Spacer()
                            if isToday(g.weekday) {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 7))
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }
            } footer: {
                Text("Calories are calculated from your macros: (carbs + protein) × 4 + fat × 9.")
            }

            if let avg = weeklyAverage {
                Section("Weekly") {
                    LabeledContent("Avg calories", value: "\(Int(avg)) kcal")
                    LabeledContent("Weekly total", value: "\(Int(avg * 7)) kcal")
                }
            }
        }
        .navigationTitle("Macro Goals")
        .task { Goals.seedIfNeeded(goals, context: context) }
    }

    private func isToday(_ weekday: Int) -> Bool {
        Calendar.current.component(.weekday, from: .now) == weekday
    }

    private var weeklyAverage: Double? {
        let set = goals.filter(\.isSet)
        guard !set.isEmpty else { return nil }
        return goals.reduce(0) { $0 + $1.calories } / 7.0
    }
}

// MARK: - Single day

struct GoalDayEditor: View {
    @Bindable var goal: MacroGoal

    @Environment(\.modelContext) private var context
    @Query(sort: \MacroGoal.weekday) private var allGoals: [MacroGoal]

    @State private var confirmCopy = false

    var body: some View {
        List {
            Section {
                macroField("Carbs", value: $goal.carbs)
                macroField("Protein", value: $goal.protein)
                macroField("Fat", value: $goal.fat)
            } header: {
                Text("Targets (grams)")
            }

            Section("Calories") {
                HStack {
                    Text("Total")
                        .font(.headline)
                    Spacer()
                    Text("\(Int(goal.calories))")
                        .font(.title2.monospacedDigit().bold())
                    Text("kcal")
                        .foregroundStyle(.secondary)
                }

                if goal.calories > 0 {
                    let s = goal.split
                    VStack(alignment: .leading, spacing: 6) {
                        SplitBar(carbs: s.carbs, protein: s.protein, fat: s.fat)
                        HStack(spacing: 12) {
                            legend(.blue, "Carbs", s.carbs)
                            legend(.green, "Protein", s.protein)
                            legend(.orange, "Fat", s.fat)
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }

            Section {
                Button {
                    confirmCopy = true
                } label: {
                    Label("Copy to all days", systemImage: "doc.on.doc")
                }
                .disabled(!goal.isSet)
            } footer: {
                Text("Overwrites every other day with these targets.")
            }
        }
        .navigationTitle(PlanWeekView.names[goal.weekday])
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDoneBar()
        .confirmationDialog("Copy these targets to all seven days?",
                            isPresented: $confirmCopy,
                            titleVisibility: .visible) {
            Button("Copy to all", role: .destructive) { copyToAll() }
            Button("Cancel", role: .cancel) { }
        }
    }

    private func macroField(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", value: value, format: .number.precision(.fractionLength(0)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
                .textFieldStyle(.roundedBorder)
            Text("g")
                .foregroundStyle(.secondary)
                .frame(width: 16, alignment: .leading)
        }
    }

    private func legend(_ color: Color, _ name: String, _ pct: Double) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text("\(name) \(Int(pct * 100))%")
        }
    }

    private func copyToAll() {
        for g in allGoals where g.weekday != goal.weekday {
            g.carbs = goal.carbs
            g.protein = goal.protein
            g.fat = goal.fat
        }
    }
}

// MARK: - Macro split bar

struct SplitBar: View {
    let carbs: Double
    let protein: Double
    let fat: Double

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                Rectangle().fill(.blue)
                    .frame(width: geo.size.width * carbs)
                Rectangle().fill(.green)
                    .frame(width: geo.size.width * protein)
                Rectangle().fill(.orange)
                    .frame(width: geo.size.width * fat)
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .frame(height: 10)
    }
}

// MARK: - Diary progress row

/// One macro's consumed / goal / remaining line with a progress bar.
struct GoalProgressRow: View {
    let label: String
    let consumed: Double
    let target: Double
    let unit: String
    let tint: Color

    private var pct: Double {
        target > 0 ? consumed / target : 0
    }
    private var remaining: Double { target - consumed }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.callout)
                Spacer()
                Text("\(Int(consumed)) / \(Int(target))\(unit)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(remaining >= 0
                     ? "\(Int(remaining)) left"
                     : "+\(Int(-remaining)) over")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(remaining >= 0 ? .secondary : .tertiary)
                    .frame(width: 76, alignment: .trailing)
            }
            ProgressView(value: min(pct, 1.0))
                .tint(pct > 1.05 ? .orange : tint)
        }
        .padding(.vertical, 2)
    }
}
