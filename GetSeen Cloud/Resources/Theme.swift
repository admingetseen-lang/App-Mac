//
//  Theme.swift
//  GetSeen Cloud
//

import SwiftUI

enum Theme {
    static let purple = Color(red: 0.48, green: 0.17, blue: 1.00) // #7b2cff
    static let blue   = Color(red: 0.10, green: 0.64, blue: 1.00) // #1aa3ff
    static let sky    = Color(red: 0.22, green: 0.74, blue: 0.97) // #38bdf8
    static let pink   = Color(red: 1.00, green: 0.42, blue: 0.42)

    static let gradient = LinearGradient(
        colors: [purple, blue],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let gradientDiagonal = LinearGradient(
        colors: [purple, blue],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Premium Button Style mit Inset-Border-Effekt
struct PremiumPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PremiumPrimaryButtonContent(configuration: configuration)
    }
}

// Eigene View damit wir @State (isHovered) nutzen können
private struct PremiumPrimaryButtonContent: View {
    let configuration: ButtonStyle.Configuration
    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(
                ZStack {
                    Theme.gradient
                    LinearGradient(colors: [Color.white.opacity(isHovered ? 0.40 : 0.30), .clear],
                                   startPoint: .top, endPoint: .center)
                        .frame(height: 12)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        LinearGradient(colors: [Theme.purple, Theme.blue],
                                       startPoint: .leading, endPoint: .trailing),
                        lineWidth: isHovered ? 2 : 1.5
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(
                color: Theme.purple.opacity(isHovered && isEnabled ? 0.55 : 0.20),
                radius: isHovered && isEnabled ? 12 : 4,
                y: isHovered && isEnabled ? 4 : 2
            )
            .opacity(isEnabled ? 1.0 : 0.55)
            .scaleEffect(configuration.isPressed ? 0.97 : (isHovered && isEnabled ? 1.03 : 1.0))
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.primary)
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(Color.primary.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Premium Badge mit Inset-Border (wie im Dashboard)
struct PremiumBadge: View {
    let text: String
    let colors: (Color, Color)

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .heavy))
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                LinearGradient(colors: [colors.0, colors.1],
                               startPoint: .leading, endPoint: .trailing)
            )
            .overlay(
                ZStack {
                    // inset Border links/rechts
                    HStack(spacing: 0) {
                        Rectangle().fill(colors.0).frame(width: 2)
                        Spacer()
                        Rectangle().fill(colors.1).frame(width: 2)
                    }
                    // Highlight oben
                    VStack(spacing: 0) {
                        Rectangle().fill(Color.white.opacity(0.30)).frame(height: 1)
                        Spacer()
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .shadow(color: Color.black.opacity(0.18), radius: 2, y: 1)
    }
}
