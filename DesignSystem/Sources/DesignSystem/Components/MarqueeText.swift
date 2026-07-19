//
//  MarqueeText.swift
//  Volspire
//
//  Single-line text that scrolls when it overflows. The scroll lives in
//  `ScrollingLine`, whose `animate` flag is LOCAL state identity-keyed on
//  (text, measured width): a fresh identity always renders at the leading
//  edge and attaches a repeatForever built from a width that matches the
//  text it's scrolling. Never hoist that flag (or the animation) to this
//  outer struct — a repeatForever whose target shifts mid-flight (new track
//  measured while the old loop runs) bakes a permanent offset into every
//  cycle via additive animation, which clipped the start of new titles.
//

import SwiftUI

public struct MarqueeText: View {
    let text: String
    private var config: Config

    @State private var textSize: CGSize = .zero

    public init(_ text: String, config: Config = .init()) {
        self.text = text
        self.config = config
    }

    public var body: some View {
        GeometryReader { geometry in
            let viewWidth = geometry.size.width
            let animatedTextVisible = textSize.width > viewWidth
            ZStack {
                ScrollingLine(
                    text: text,
                    viewWidth: viewWidth,
                    lineWidth: lineWidth,
                    leftFade: config.leftFade,
                    animation: animation
                )
                // Identity = text + measured width. Any change tears down the
                // subtree AND its repeatForever (the only reliable cancel);
                // the replacement starts at the leading edge. A mid-measure
                // restart lands inside `startDelay`, so it's invisible.
                .id("\(text)|\(Int(textSize.width))")
                .mask(fadeMask)
                .hidden(!animatedTextVisible)

                staticText
                    .hidden(animatedTextVisible)
            }
        }
        .frame(height: textSize.height)
        .overlay {
            Text(text)
                .padding(.leading, config.leftFade)
                .padding(.trailing, config.rightFade)
                .lineLimit(1)
                .fixedSize()
                .sizeReader(size: $textSize)
                .hidden()
        }
    }

    public struct Config {
        var startDelay: Double
        var alignment: Alignment
        var leftFade: CGFloat
        var rightFade: CGFloat
        var spacing: CGFloat

        public init(
            startDelay: Double = 1.0,
            alignment: Alignment = .leading,
            leftFade: CGFloat = 40,
            rightFade: CGFloat = 40,
            spacing: CGFloat = 100
        ) {
            self.startDelay = startDelay
            self.alignment = alignment
            self.leftFade = leftFade
            self.rightFade = rightFade
            self.spacing = spacing
        }
    }
}

private extension MarqueeText {
    var lineWidth: CGFloat { textSize.width - (config.leftFade + config.rightFade) + config.spacing }

    var staticText: some View {
        Text(text)
            .padding(.leading, config.leftFade)
            .padding(.trailing, config.rightFade)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: config.alignment)
    }

    var animation: Animation {
        .linear(duration: Double(textSize.width) / 30)
            .delay(config.startDelay)
            .repeatForever(autoreverses: false)
    }

    var fadeMask: some View {
        HStack(spacing: 0) {
            LinearGradient(
                gradient: Gradient(colors: [.black.opacity(0), .black]),
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: config.leftFade)
            LinearGradient(
                gradient: Gradient(colors: [.black, .black]),
                startPoint: .leading,
                endPoint: .trailing
            )
            LinearGradient(
                gradient: Gradient(colors: [.black, .black.opacity(0)]),
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: config.rightFade)
        }
        // NO horizontal padding here: a padded mask paints nothing over the
        // outer points of the view, which CLIPPED the first glyph of every
        // scrolling title (only the overflow branch is masked — static
        // titles were fine, which is why it looked like a scroll bug).
    }
}

/// The scrolling pair of texts. `animate` is deliberately local: it resets
/// with this view's identity, so every (text, width) combination starts at
/// offset 0 and owns exactly one animation for its lifetime.
private struct ScrollingLine: View {
    let text: String
    let viewWidth: CGFloat
    let lineWidth: CGFloat
    let leftFade: CGFloat
    let animation: Animation

    @State private var animate = false

    private var offset: Double { animate ? lineWidth : 0 }

    var body: some View {
        Group {
            Text(text)
                .offset(x: -offset)
            Text(text)
                .offset(x: -offset + lineWidth)
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .frame(width: viewWidth)
        .offset(x: leftFade)
        .onAppear {
            withAnimation(animation) { animate = true }
        }
    }
}

#Preview {
    HStack {
        MarqueeText(
            "Lorem ipsum dolor sit amet, consectetur adipiscing elit",
            config: .init(
                startDelay: 3,
                leftFade: 32,
                rightFade: 32
            )
        )
        .background(.pink.opacity(0.6))

        Text("Normal Text")
            .background(.mint.opacity(0.6))
    }
    .padding(.horizontal, 16)
    .font(.largeTitle)
}
