//
//  ContentView.swift
//  suon
//
//  Created by user289721 on 5/16/26.
//

import SwiftUI

struct ContentView: View {
    @State private var showSplash: Bool = true
    @State private var isLoading: Bool = true
    @State private var progress: Double = 0
    @State private var canGoBack: Bool = false
    @State private var canGoForward: Bool = false

    private let url = URL(string: "https://meem-38f4b.web.app/")!

    var body: some View {
        ZStack {
            WebContainerView(
                url: url,
                isLoading: $isLoading,
                progress: $progress,
                canGoBack: $canGoBack,
                canGoForward: $canGoForward
            )
            .ignoresSafeArea(edges: .bottom)

            if showSplash {
                SplashView()
                    .transition(.opacity.combined(with: .scale(scale: 1.08)))
                    .zIndex(10)
            }
        }
        .task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            withAnimation(.easeInOut(duration: 0.55)) {
                showSplash = false
            }
        }
    }
}

struct WebContainerView: View {
    let url: URL
    @Binding var isLoading: Bool
    @Binding var progress: Double
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool

    var body: some View {
        VStack(spacing: 0) {
            if isLoading && progress < 1 {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(.accentColor)
                    .frame(height: 2)
                    .transition(.opacity)
            }
            WebView(
                url: url,
                isLoading: $isLoading,
                estimatedProgress: $progress,
                canGoBack: $canGoBack,
                canGoForward: $canGoForward
            )
        }
        .background(Color(.systemBackground))
    }
}

#Preview {
    ContentView()
}
