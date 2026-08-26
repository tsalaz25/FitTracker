//
//  ActiveWorkoutView.swift
//  FitTracker
//
//  Created by Tomas Salaz on 8/25/26.
//

import SwiftUI
import SwiftData
import Combine

struct ActiveWorkoutView: View {
    @Bindable var session: WorkoutSession

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var rest = RestTimer()
    @State private var picking = false
    @State private var confirmFinish = false
    @State private var now = Date.now

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Label(TimeFormat.hms(now.timeIntervalSince(session.start)),
                              systemImage: "clock")
                            .monospacedDigit()
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            if session.totalVolume > 0 {
                                Text("\(Int(session.totalVolume)) lb")
                                    .font(.caption.monospacedDigit())
                            }
                            if session.totalMiles > 0 {
                                Text(TimeFormat.distance(session.totalMiles))
                                    .font(.caption.monospacedDigit())
                            }
                        }
                        .foregroundStyle(.secondary)
                    }
                }

                ForEach(session.sortedExercises) { pe in
                    ExerciseBlock(performed: pe, session: session, rest: rest)
                }

                Section {
                    Button {
                        picking = true
                    } label: {
                        Label("Add exercise", systemImage: "plus")
                    }
                }
            }
            .navigationTitle(session.title)
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                if rest.isRunning { restBar }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Finish") { confirmFinish = true }
                        .bold()
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard", role: .destructive) {
                        rest.stop()
                        context.delete(session)
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $picking) {
                ExercisePicker { addExercise($0) }
            }
            .confirmationDialog("Finish this workout?",
                                isPresented: $confirmFinish,
                                titleVisibility: .visible) {
                Button("Finish") { finish() }
                Button("Keep going", role: .cancel) { }
            }
            .onReceive(tick) { now = $0 }
        }
        .interactiveDismissDisabled()
    }

    // MARK: - Rest bar

    private var restBar: some View {
        HStack {
            Text(rest.display)
                .font(.title2.monospacedDigit().bold())
            Spacer()
            Button("-15") { rest.add(-15) }
            Button("+15") { rest.add(15) }
            Button("Skip") { rest.stop() }
        }
        .buttonStyle(.bordered)
        .padding()
        .background(.regularMaterial)
    }

    // MARK: - Actions

    private func addExercise(_ ex: Exercise) {
        let pe = PerformedExercise(exerciseID: ex.id,
                                   exerciseName: ex.name,
                                   order: session.performed.count,
                                   mode: ex.isCardio ? .cardio : .strength)
        pe.sets.append(SetLog(index: 0))
        session.performed.append(pe)
    }

    private func finish() {
        // Drop rows that were never ticked off.
        for pe in session.performed {
            let incomplete = pe.sets.filter { !$0.isComplete }
            for s in incomplete {
                if let idx = pe.sets.firstIndex(where: { $0.persistentModelID == s.persistentModelID }) {
                    let removed = pe.sets.remove(at: idx)
                    context.delete(removed)
                }
            }
        }

        let empties = session.performed.filter { $0.sets.isEmpty }
        for pe in empties {
            if let idx = session.performed.firstIndex(where: { $0.persistentModelID == pe.persistentModelID }) {
                let removed = session.performed.remove(at: idx)
                context.delete(removed)
            }
        }

        session.end = .now
        rest.stop()
        dismiss()
    }
}

// MARK: - One exercise block

struct ExerciseBlock: View {
    @Bindable var performed: PerformedExercise
    let session: WorkoutSession
    let rest: RestTimer

    @Environment(\.modelContext) private var context
    @State private var last: SetLog?

    private var isCardio: Bool { performed.mode == .cardio }

    var body: some View {
        Section {
            if isCardio {
                HStack(spacing: 10) {
                    Text("#").frame(width: 18)
                    Text("Time").frame(width: 72)
                    Text("Pace").frame(width: 72)
                    Spacer()
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            ForEach(performed.sortedSets) { set in
                SetRow(set: set, isCardio: isCardio, rest: rest)
            }
            .onDelete(perform: deleteSet)

            Button {
                addSet()
            } label: {
                Label(isCardio ? "Add rep" : "Add set", systemImage: "plus.circle")
                    .font(.caption)
            }
        } header: {
            HStack {
                Text(performed.exerciseName)
                Spacer()
                headerDetail
            }
        }
        .task {
            last = WorkoutEngine.lastPerformance(exerciseID: performed.exerciseID,
                                                 excluding: session,
                                                 context: context)
        }
    }

    @ViewBuilder
    private var headerDetail: some View {
        if isCardio {
            if performed.totalMiles > 0 {
                Text(TimeFormat.distance(performed.totalMiles))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if let p = last?.paceString {
                Text("best: \(p)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } else if let last, let w = last.weight, let r = last.reps {
            Text("last: \(Int(w))×\(r)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func addSet() {
        let next = SetLog(index: performed.sets.count)
        if let prev = performed.sortedSets.last {
            next.reps = prev.reps
            next.weight = prev.weight
            next.durationSeconds = prev.durationSeconds
            next.paceSecondsPerMile = prev.paceSecondsPerMile
        }
        performed.sets.append(next)
    }

    private func deleteSet(_ offsets: IndexSet) {
        let list = performed.sortedSets
        for i in offsets {
            if let idx = performed.sets.firstIndex(where: {
                $0.persistentModelID == list[i].persistentModelID
            }) {
                let removed = performed.sets.remove(at: idx)
                context.delete(removed)
            }
        }
        for (i, s) in performed.sortedSets.enumerated() { s.index = i }
    }
}

// MARK: - One row

struct SetRow: View {
    @Bindable var set: SetLog
    let isCardio: Bool
    let rest: RestTimer

    var body: some View {
        HStack(spacing: 10) {
            Text("\(set.index + 1)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 18)

            if isCardio {
                TimeField(seconds: $set.durationSeconds, placeholder: "time")
                TimeField(seconds: $set.paceSecondsPerMile, placeholder: "pace")
                if let d = set.distanceString {
                    Text(d)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            } else {
                NumberField(value: $set.weight, placeholder: "lb")
                Text("×").foregroundStyle(.secondary)
                IntField(value: $set.reps, placeholder: "reps")
            }

            Spacer()

            Button {
                set.isComplete.toggle()
                if set.isComplete { rest.start() }
            } label: {
                Image(systemName: set.isComplete ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(set.isComplete ? .green : .secondary)
            }
            .buttonStyle(.plain)
        }
        .listRowBackground(set.isComplete ? Color.green.opacity(0.10) : Color.clear)
    }
}
