//
//  SplashView.swift
//  LOLIVE
//

import SwiftUI

struct SplashView: View {
    @State private var scale: CGFloat = 0.85
    @State private var opacity: Double = 0.0
    @State private var subtitleOpacity: Double = 0.0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 18) {
                Image("AppIconImage")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 108, height: 108)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .shadow(color: .blue.opacity(0.35), radius: 24, x: 0, y: 8)

                VStack(spacing: 6) {
                    Text("LOLIVE")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("LoL Esports Companion")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.45))
                        .opacity(subtitleOpacity)
                }
            }
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear {
                withAnimation(.spring(duration: 0.55, bounce: 0.25)) {
                    scale = 1.0
                    opacity = 1.0
                }
                withAnimation(.easeIn(duration: 0.4).delay(0.35)) {
                    subtitleOpacity = 1.0
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    SplashView()
}
