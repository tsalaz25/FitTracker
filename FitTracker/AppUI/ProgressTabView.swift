//
//  ProgressTabView.swift
//  FitTracker
//
//  Created by Tomas Salaz on 8/25/26.
//

import SwiftUI
import SwiftData
import Charts

struct ProgressTabView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \WeightEntry.date, order: .reverse) private var weights: [WeightEntry]
    @Query(sort: \WorkoutSession.start, order: .reverse) private var sessions: [WorkoutSession]

    @State private var input = ""

    private var finished: [WorkoutSession] { sessions.filter { $0.end != nil } }

    /// Oldest-first, for charting.
    private var chronological: [WeightEntry] { weights.reversed() }

    private var sevenDayAverage: Double? {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: .now)!
        let recent = weights.filter { $0.date >= cutoff }
        guard !recent.isEmpty else { return nil }
        return recent.reduce(0) { $0 + $1.pounds } / Double(recent.count)
    }

    private var weeklyVolume: Double {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: .now)!
        return finished.filter { $0.start >= cutoff }
                       .reduce(0) { $0 + $1.totalVolume }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Log weight") {
                    HStack {
                        TextField("Weight (lbs)", text: $input)
                            .keyboardType(.decimalPad)
                        Button("Add") {
                            guard let lbs = Double(input), lbs > 0 else { return }
                            context.insert(WeightEntry(pounds: lbs))
                            input = ""
                        }
                        .disabled(Double(input) == nil)
                    }
                }

                if let avg = sevenDayAverage {
                    Section("This week") {
                        LabeledContent("7-day avg weight",
                                       value: avg,
                                       format: .number.precision(.fractionLength(1)))
                        LabeledContent("Workouts", value: "\(weekWorkoutCount)")
                        if weeklyVolume > 0 {
                            LabeledContent("Volume", value: "\(Int(weeklyVolume)) lb")
                        }
                    }
                }

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

                Section("History") {
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
                    .onDelete { idx in
                        for i in idx { context.delete(weights[i]) }
                    }
                }
            }
            .navigationTitle("Progress")
        }
    }

    private var weekWorkoutCount: Int {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: .now)!
        return finished.filter { $0.start >= cutoff }.count
    }
}
