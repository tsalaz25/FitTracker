//
//  WorkoutEngine.swift
//  FitTracker
//
//  Created by Tomas Salaz on 8/25/26.
//

import Foundation
import SwiftData
import Observation

enum WorkoutEngine {

    static let warmupBlockID = "warmup-block"

    /// Builds a session from a plan day, copying each planned set with
    /// its type and rep target. A non-empty warm-up note becomes a
    /// single 1×1 block at the top.
    static func start(from day: PlanDay, context: ModelContext) -> WorkoutSession {
        let title = day.title.isEmpty ? "Workout" : day.title

        let session = WorkoutSession(title: title)
        context.insert(session)

        // Warm-up block first, at order -1 so it always sorts to the top.
        let note = day.warmupNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty {
            let block = PerformedExercise(exerciseID: warmupBlockID,
                                          exerciseName: "Warm-Up",
                                          order: -1,
                                          mode: .strength)
            context.insert(block)
            block.isWarmupBlock = true
            block.notes = note

            let s = SetLog(index: 0, type: .warmup)
            context.insert(s)
            block.sets.append(s)

            session.performed.append(block)
        }

        for item in day.sorted {
            let pe = PerformedExercise(exerciseID: item.exerciseID,
                                       exerciseName: item.exerciseName,
                                       order: item.order,
                                       mode: item.mode)
            context.insert(pe)
            pe.notes = item.notes

            switch item.mode {
            case .cardio:
                for i in 0..<max(1, item.targetIntervals) {
                    let s = SetLog(index: i)
                    context.insert(s)
                    s.durationSeconds = item.targetIntervalSeconds
                    s.paceSecondsPerMile = item.targetPaceSecondsPerMile
                    pe.sets.append(s)
                }

            case .strength:
                let planned = item.sortedSets
                if planned.isEmpty {
                    let s = SetLog(index: 0)
                    context.insert(s)
                    pe.sets.append(s)
                } else {
                    for (i, ps) in planned.enumerated() {
                        let s = SetLog(index: i, type: ps.type)
                        context.insert(s)
                        s.targetReps = ps.reps
                        pe.sets.append(s)
                    }
                }
            }

            session.performed.append(pe)
        }

        return session
    }

    static func startBlank(context: ModelContext) -> WorkoutSession {
        let session = WorkoutSession(title: "Quick Workout")
        context.insert(session)
        return session
    }

    /// Best previous performance for an exercise, excluding the current
    /// session and ignoring warm-ups.
    static func lastPerformance(exerciseID: String,
                                excluding current: WorkoutSession?,
                                context: ModelContext) -> SetLog? {
        guard exerciseID != warmupBlockID else { return nil }

        let descriptor = FetchDescriptor<WorkoutSession>(
            sortBy: [SortDescriptor(\.start, order: .reverse)]
        )
        guard let sessions = try? context.fetch(descriptor) else { return nil }

        for session in sessions {
            if let current, session.persistentModelID == current.persistentModelID { continue }
            guard session.end != nil else { continue }

            let matches = session.performed
                .filter { $0.exerciseID == exerciseID }
                .flatMap(\.sets)
                .filter { $0.isComplete && $0.type.countsAsWork }

            guard !matches.isEmpty else { continue }

            let best = matches.max { a, b in
                if let aw = a.weight, let bw = b.weight { return aw < bw }
                let ap = a.paceSecondsPerMile ?? .greatestFiniteMagnitude
                let bp = b.paceSecondsPerMile ?? .greatestFiniteMagnitude
                return ap > bp
            }
            if let best { return best }
        }
        return nil
    }

    static func todaysPlan(from days: [PlanDay]) -> PlanDay? {
        let wd = Calendar.current.component(.weekday, from: .now)
        return days.first { $0.weekday == wd }
    }
}

// MARK: - Rest timer

@Observable
final class RestTimer {
    private(set) var remaining: Int = 0
    private(set) var isRunning = false
    var defaultLength = 90

    @ObservationIgnored private var timer: Timer?

    func start(_ seconds: Int? = nil) {
        remaining = seconds ?? defaultLength
        isRunning = true
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.remaining > 0 {
                self.remaining -= 1
            } else {
                self.stop()
            }
        }
    }

    func add(_ seconds: Int) {
        guard isRunning else { return }
        remaining = max(0, remaining + seconds)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        remaining = 0
    }

    var display: String {
        String(format: "%d:%02d", remaining / 60, remaining % 60)
    }
}
