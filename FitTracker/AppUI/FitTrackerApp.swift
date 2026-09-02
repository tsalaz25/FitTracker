//
//  FitTrackerApp.swift
//  FitTracker
//
//  Created by Tomas Salaz on 8/25/26.
//

import SwiftUI
import SwiftData

@main
struct FitTrackerApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [
            Food.self,
            FoodEntry.self,
            WeightEntry.self,
            MacroGoal.self,
            PlanDay.self,
            PlanExercise.self,
            PlanSet.self,
            WorkoutSession.self,
            PerformedExercise.self,
            SetLog.self
        ])
    }
}
