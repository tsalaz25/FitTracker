//
//  ProgressTabView.swift
//  FitTracker
//
//  Created by Tomas Salaz on 8/25/26.
//

import SwiftUI
import SwiftData
import Charts

/// One day's calories alongside that day's goal.
struct DayCalories: Identifiable {
    let date: Date
    let consumed: Double
    let goal: Double
    var id: Date { date }
}

struct ProgressTabView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \WeightEntry.date, order: .reverse) private var weights: [WeightEntry]
    @Query(sort: \WorkoutSession.start, order: .reverse) private var sessions: [WorkoutSession]
    @Query(sort: \MacroGoal.weekday) private var goals: [MacroGoal]
    @Query private var entries: [FoodEntry]

    @State private var input = ""

    var body: some View {
        NavigationStack {
            List {
                goalsLink
                weightEntry
                weekSummary
                weightChart
                calorieChart
                weightHistory
            }
            .navigationTitle("Progress")
            .keyboardDoneBar()
            .task { Goals.seedIfNeeded(goals, context: context) }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var goalsLink: some View {
        Section {
            NavigationLink {
                GoalsEditorView()
            } label: {
                HStack {
                    Label("Macro Goals", systemImage: "target")
                    Spacer()
                    Text(todayGoalSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var weightEntry: some View {
        Section("Log weight") {
            HStack {
                TextField("Weight (lbs)", text: $input)
                    .keyboardType(.decimalPad)
                Button("Add") { addWeight() }
                    .disabled(Double(input) == nil)
            }
        }
    }

    @ViewBuilder
    private var weekSummary: some View {
        Section("This week") {
            if let avg = sevenDayAverage {
                LabeledContent("7-day avg weight",
                               value: avg,
                               format: .number.precision(.fractionLength(1)))
            }
            LabeledContent("Workouts", value: "\(weekWorkoutCount)")
            if weeklyVolume > 0 {
                LabeledContent("Volume", value: "\(Int(weeklyVolume)) lb")
            }
            if let adherence = weekAdherence {
                LabeledContent("Days on target", value: adherence)
            }
        }
    }

    @ViewBuilder
    private var weightChart: some View {
        if chronological.count >= 2 {
            Section("Weight trend") {
                Chart(chronological) { e in
                    LineMark(x: .value("Date", e.date),
                             y: .value("Pounds", e.pounds))
                    PointMark(x: .value("Date", e.date),
                              y: .value("Pounds", e.pounds))
                        .symbolSize(20)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 200)
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private var calorieChart: some View {
        let history = calorieHistory
        if !history.isEmpty {
            Section("Calories vs goal") {
                Chart(history) { d in
                    BarMark(x: .value("Day", d.date, unit: .day),
                            y: .value("Calories", d.consumed))
                        .foregroundStyle(barColor(d))
                }
                .frame(height: 180)
                .padding(.vertical, 4)

                if let goalLine = averageGoal(history) {
                    Text("Goal averages \(Int(goalLine)) kcal over this period")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var weightHistory: some View {
        Section("Weight history") {
            if weights.isEmpty {
                Text("No entries yet").foregroundStyle(.secondary)
            }
            ForEach(weights) { e in
                HStack {
                    Text(e.pounds, format: .number.precision(.fractionLength(1)))
                        .monospacedDigit()
                    Spacer()
                    Text(e.date, style: .date)
                        .foregroundStyle(.secondary)
                }
            }
            .onDelete(perform: deleteWeights)
        }
    }

    // MARK: - Actions

    private func addWeight() {
        guard let lbs = Double(input), lbs > 0 else { return }
        context.insert(WeightEntry(pounds: lbs))
        input = ""
    }

    private func deleteWeights(_ idx: IndexSet) {
        for i in idx { context.delete(weights[i]) }
    }

    private func barColor(_ d: DayCalories) -> Color {
        guard d.goal > 0 else { return .accentColor }
        return d.consumed > d.goal ? .orange : .accentColor
    }

    private func averageGoal(_ history: [DayCalories]) -> Double? {
        let withGoals = history.filter { $0.goal > 0 }
        guard !withGoals.isEmpty else { return nil }
        return withGoals.reduce(0.0) { $0 + $1.goal } / Double(withGoals.count)
    }

    // MARK: - Derived values

    private var finished: [WorkoutSession] {
        sessions.filter { $0.end != nil }
    }

    private var chronological: [WeightEntry] {
        weights.reversed()
    }

    private var todayGoalSummary: String {
        Goals.goal(for: .now, in: goals)?.summary ?? "Not set"
    }

    private var sevenDayAverage: Double? {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: .now) else {
            return nil
        }
        let recent = weights.filter { $0.date >= cutoff }
        guard !recent.isEmpty else { return nil }
        let sum = recent.reduce(0.0) { $0 + $1.pounds }
        return sum / Double(recent.count)
    }

    private var weekWorkoutCount: Int {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: .now) else {
            return 0
        }
        return finished.filter { $0.start >= cutoff }.count
    }

    private var weeklyVolume: Double {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: .now) else {
            return 0
        }
        return finished.filter { $0.start >= cutoff }
                       .reduce(0.0) { $0 + $1.totalVolume }
    }

    /// Last 14 days that have any logged food.
    private var calorieHistory: [DayCalories] {
        let cal = Calendar.current
        var out: [DayCalories] = []

        for offset in stride(from: 13, through: 0, by: -1) {
            guard let d = cal.date(byAdding: .day, value: -offset, to: .now) else { continue }

            let dayEntries = entries.filter { cal.isDate($0.date, inSameDayAs: d) }
            guard !dayEntries.isEmpty else { continue }

            let consumed = dayEntries.reduce(0.0) { running, entry in
                running + (entry.food?.amount(of: Nutrient.calories, grams: entry.grams) ?? 0)
            }
            let goal = Goals.goal(for: d, in: goals)?.calories ?? 0
            out.append(DayCalories(date: d, consumed: consumed, goal: goal))
        }
        return out
    }

    /// How many of the last 7 logged days landed within 10% of goal.
    private var weekAdherence: String? {
        let recent = calorieHistory.suffix(7).filter { $0.goal > 0 }
        guard !recent.isEmpty else { return nil }
        let hits = recent.filter { abs($0.consumed - $0.goal) / $0.goal <= 0.10 }.count
        return "\(hits) / \(recent.count)"
    }
}
