//
//  TrainTabView.swift
//  FitTracker
//
//  Created by Tomas Salaz on 8/25/26.
//

import SwiftUI
import SwiftData

struct TrainTabView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \PlanDay.weekday) private var days: [PlanDay]
    @Query(sort: \WorkoutSession.start, order: .reverse) private var sessions: [WorkoutSession]

    @State private var active: WorkoutSession?

    private var today: PlanDay? { WorkoutEngine.todaysPlan(from: days) }
    private var finished: [WorkoutSession] { sessions.filter { $0.end != nil } }

    var body: some View {
        NavigationStack {
            List {
                Section("Today") {
                    if let today, !today.isRestDay, !today.items.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(today.title.isEmpty ? "Workout" : today.title)
                                .font(.headline)
                            Text(today.sorted.map(\.exerciseName).joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }

                        Button {
                            active = WorkoutEngine.start(from: today, context: context)
                        } label: {
                            Label("Start Workout", systemImage: "play.fill")
                                .bold()
                        }
                    } else {
                        Text(today?.isRestDay == true ? "Rest day" : "No exercises planned")
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        active = WorkoutEngine.startBlank(context: context)
                    } label: {
                        Label("Empty workout", systemImage: "plus")
                            .font(.callout)
                    }
                }

                Section("History") {
                    if finished.isEmpty {
                        Text("No workouts yet").foregroundStyle(.secondary)
                    }
                    ForEach(finished) { s in
                        NavigationLink {
                            WorkoutDetailView(session: s)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.title)
                                HStack(spacing: 6) {
                                    Text(s.start, style: .date)
                                    Text("·")
                                    Text("\(Int(s.duration / 60)) min")
                                    if s.totalVolume > 0 {
                                        Text("·")
                                        Text("\(Int(s.totalVolume)) lb")
                                    }
                                    if s.totalMiles > 0 {
                                        Text("·")
                                        Text(TimeFormat.distance(s.totalMiles))
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { idx in
                        for i in idx { context.delete(finished[i]) }
                    }
                }
            }
            .navigationTitle("Train")
            .fullScreenCover(item: $active) { s in
                ActiveWorkoutView(session: s)
            }
        }
    }
}

// MARK: - Past workout detail

struct WorkoutDetailView: View {
    let session: WorkoutSession

    var body: some View {
        List {
            Section {
                LabeledContent("Date", value: session.start.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Duration", value: TimeFormat.hms(session.duration))
                if session.totalVolume > 0 {
                    LabeledContent("Volume", value: "\(Int(session.totalVolume)) lb")
                }
                if session.totalMiles > 0 {
                    LabeledContent("Distance", value: TimeFormat.distance(session.totalMiles))
                }
            }

            ForEach(session.sortedExercises) { pe in
                Section(pe.exerciseName) {
                    ForEach(pe.sortedSets) { s in
                        HStack {
                            Text("\(s.index + 1)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 18)
                            if pe.mode == .cardio {
                                Text(s.durationSeconds.map { TimeFormat.mmss($0) } ?? "—")
                                Text("@").foregroundStyle(.secondary)
                                Text(s.paceString ?? "—")
                                Spacer()
                                Text(s.distanceString ?? "—")
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("\(Int(s.weight ?? 0)) lb")
                                Text("×").foregroundStyle(.secondary)
                                Text("\(s.reps ?? 0)")
                                Spacer()
                            }
                        }
                        .font(.callout.monospacedDigit())
                    }
                }
            }
        }
        .navigationTitle(session.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
