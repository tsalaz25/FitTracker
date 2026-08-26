//
//  RootView.swift
//  FitTracker
//
//  Created by Tomas Salaz on 8/25/26.
//

import SwiftUI
 
struct RootView: View {
    var body: some View {
        TabView {
            DiaryView()
                .tabItem { Label("Diary", systemImage: "fork.knife") }
 
            TrainTabView()
                .tabItem { Label("Train", systemImage: "figure.strengthtraining.traditional") }
 
            PlanWeekView()
                .tabItem { Label("Plan", systemImage: "calendar") }
 
            ProgressTabView()
                .tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }
 
            ExerciseBrowserView()
                .tabItem { Label("Exercises", systemImage: "list.bullet") }
        }
    }
}
 










