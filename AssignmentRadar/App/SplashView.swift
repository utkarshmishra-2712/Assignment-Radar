//
//  SplashView.swift
//  AssignmentRadar
//
//  Seamless in-app splash view rendered immediately upon app launch.
//  Matches the exact geometry, colors, and positioning of the iOS static launch screen
//  with an optional subtle pulse on the radar center dot.
//

import SwiftUI

struct SplashView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var isPulsing: Bool = false

    var body: some View {
        ZStack {
            // Background matching exact theme background (#F6F9F8 light, #0F1F1E dark)
            Theme.backgroundColor(for: colorScheme)
                .ignoresSafeArea()

            // Centered 120pt Radar Logo
            ZStack {
                Image("LaunchLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)

                // Subtle coral center ping / radar pulse
                Circle()
                    .fill(Color(hex: 0xFF6B4A).opacity(isPulsing ? 0.0 : 0.6))
                    .frame(width: isPulsing ? 24 : 12, height: isPulsing ? 24 : 12)
                    .allowsHitTesting(false)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false)) {
                isPulsing = true
            }
        }
    }
}

#Preview {
    SplashView()
}
