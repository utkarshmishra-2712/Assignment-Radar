//
//  RootView.swift
//  AssignmentRadar
//
//  Coordinates transitions between SplashView and MainView based on
//  AppBootstrapper readiness, featuring a seamless 0.25-second crossfade.
//

import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var themeManager: ThemeManager

    @State private var bootstrapper = AppBootstrapper()

    var body: some View {
        ZStack {
            // Base background matching exact theme background (#F6F9F8 light, #0F1F1E dark)
            Theme.backgroundColor(for: colorScheme)
                .ignoresSafeArea()

            if bootstrapper.isReady {
                MainView()
                    .transition(.opacity)
            } else {
                SplashView()
                    .transition(.opacity)
            }

            // Safety timeout banner if startup watchdog triggered
            if let warning = bootstrapper.startupWarningMessage {
                VStack {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(Theme.accent)
                        Text(warning)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(Theme.textColor(for: colorScheme))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Theme.cardColor(for: colorScheme))
                    .clipShape(Capsule())
                    .shadow(radius: 6)
                    .padding(.top, 12)

                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.25), value: bootstrapper.isReady)
        .task {
            await bootstrapper.bootstrap(
                modelContainer: modelContext.container,
                themeManager: themeManager
            )
        }
    }
}

#Preview {
    RootView()
        .environmentObject(ThemeManager())
        .modelContainer(for: DeadlineItem.self, inMemory: true)
}
