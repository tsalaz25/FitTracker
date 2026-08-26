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

    /// Builds a session from a plan day, pre-filling empty sets/intervals.
    static func start(from day: PlanDay, context: ModelContext) -> WorkoutSession {
        let title = day.title.isEmpty ? "Workout" : day.title
        let session = WorkoutSession(title: title)

        for item in day.sorted {
            let pe = PerformedExercise(exerciseID: item.exerciseID,
                                       exerciseName: item.exerciseName,
                                       order: item.order,
                                       mode: item.mode)
            switch item.mode {
            case .cardio:
                for i in 0..<max(1, item.targetIntervals) {
                    let s = SetLog(index: i)
                    s.durationSeconds = item.targetIntervalSeconds
                    s.paceSecondsPerMile = item.targetPaceSecondsPerMile
                    pe.sets.append(s)
                }
            case .strength:
                for i in 0..<max(1, item.targetSets) {
                    let s = SetLog(index: i)
                    s.reps = item.targetReps
                    pe.sets.append(s)
                }
            }
            session.performed.append(pe)
        }

        context.insert(session)
        return session
    }

    /// Empty session for ad-hoc training.
    static func startBlank(context: ModelContext) -> WorkoutSession {
        let session = WorkoutSession(title: "Quick Workout")
        context.insert(session)
        return session
    }

    /// Best previous performance for an exercise, excluding the current session.
    /// Strength: heaviest completed set. Cardio: fastest completed pace.
    static func lastPerformance(exerciseID: String,
                                excluding current: WorkoutSession?,
                                context: ModelContext) -> SetLog? {
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
                .filter(\.isComplete)

            guard !matches.isEmpty else { continue }

            let best = matches.max { a, b in
                if let aw = a.weight, let bw = b.weight { return aw < bw }
                // Faster pace is better, so invert.
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
