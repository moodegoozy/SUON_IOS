//
//  SplashView.swift
//  suon
//

import SwiftUI

struct SplashView: View {
    @State private var scale: CGFloat = 0.6
    @State private var opacity: Double = 0.0
    @State private var glow: Double = 0.0

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.07, blue: 0.15),
                    Color(red: 0.10, green: 0.13, blue: 0.25),
                    Color(red: 0.03, green: 0.05, blue: 0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.18), Color.clear],
                        center: .center,
                        startRadius: 5,
                        endRadius: 260
                    )
                )
                .frame(width: 520, height: 520)
                .opacity(glow)
                .blur(radius: 30)

            VStack(spacing: 24) {
                Image("Logo")
                    .resizable()
                    .renderingMode(.original)
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 180, height: 180)
                    .shadow(color: .white.opacity(0.25), radius: 20, x: 0, y: 8)
                    .scaleEffect(scale)
                    .opacity(opacity)

                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white.opacity(0.85))
                    .opacity(opacity)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.55)) {
                scale = 1.0
                opacity = 1.0
            }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                glow = 1.0
            }
        }
    }
}

#Preview {
    SplashView()
}
