import SwiftUI

/// The notch gestures the gestures page demonstrates, in the order they play.
enum OnboardingGesture: Int, CaseIterable, Identifiable, Sendable {
    case hover
    case click
    case swipe
    case dropFiles

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .hover: "Hover"
        case .click: "Click"
        case .swipe: "Swipe"
        case .dropFiles: "Drop Files"
        }
    }

    var detail: String {
        switch self {
        case .hover: "Rest the pointer on the notch and it opens."
        case .click: "Click the notch to open it right away."
        case .swipe: "Two-finger swipe down to open, up to close."
        case .dropFiles: "Drag files onto the notch to keep them on the Shelf."
        }
    }

    var systemImage: String {
        switch self {
        case .hover: "cursorarrow.rays"
        case .click: "cursorarrow.click"
        case .swipe: "hand.draw"
        case .dropFiles: "tray.and.arrow.down"
        }
    }
}

/// Teaches the notch: a looping miniature of the island responding to each gesture, with the
/// matching row highlighted. Clicking a row jumps the demo to it.
struct OnboardingGesturesPage: View {
    let onContinue: () -> Void

    @StateObject private var demo = OnboardingNotchDemoModel()

    var body: some View {
        VStack(spacing: 18) {
            Text("Meet Your Notch")
                .font(.title)
                .fontWeight(.semibold)
                .padding(.top, 32)

            Text("The notch opens into an island with your music, calendar, files and tools. Four gestures do it all.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 28)

            OnboardingNotchDemo(model: demo)
                .frame(width: 336, height: 136)

            VStack(spacing: 4) {
                ForEach(OnboardingGesture.allCases) { gesture in
                    gestureRow(gesture)
                }
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 0)

            Button("Continue", action: onContinue)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onboardingPageBackground()
        .onAppear { demo.start() }
        .onDisappear { demo.stop() }
    }

    private func gestureRow(_ gesture: OnboardingGesture) -> some View {
        let isActive = demo.gesture == gesture
        return Button {
            demo.start(from: gesture)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: gesture.systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isActive ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1))
                    )
                VStack(alignment: .leading, spacing: 1) {
                    Text(gesture.title)
                        .font(.headline)
                    Text(gesture.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isActive ? Color.accentColor.opacity(0.08) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.smooth(duration: 0.25), value: isActive)
    }
}

/// What the miniature shows at a given moment.
enum OnboardingDemoIsland: Equatable, Sendable {
    case closed
    case hovered
    /// Stretched by a swipe that has not opened it yet.
    case stretched
    case open
}

enum OnboardingDemoProp: Equatable, Sendable {
    case none
    case pointer
    case twoFingers
    case file
}

/// Script for the miniature: each gesture is a short sequence of poses separated by pauses.
@MainActor
final class OnboardingNotchDemoModel: ObservableObject {
    @Published private(set) var gesture: OnboardingGesture = .hover
    @Published private(set) var island: OnboardingDemoIsland = .closed
    @Published private(set) var prop: OnboardingDemoProp = .none
    /// Prop position in unit coordinates of the demo screen.
    @Published private(set) var propPosition = CGPoint(x: 0.2, y: 0.85)
    @Published private(set) var clickPulse = 0
    @Published private(set) var showsShelfItem = false
    /// Direction of the swipe arrow: down to open, up to close.
    @Published private(set) var swipeOpens = true

    private var loop: Task<Void, Never>?

    /// The island's own springs: open (response 0.42, damping 1), close (0.45, 1) and the
    /// hover bounce.
    static let openSpring = Animation.spring(response: 0.42, dampingFraction: 1, blendDuration: 0)
    static let closeSpring = Animation.spring(response: 0.45, dampingFraction: 1, blendDuration: 0)
    static let hoverSpring = Animation.bouncy.speed(1.2)
    static let propMove = Animation.easeInOut(duration: 0.7)

    func start(from first: OnboardingGesture = .hover) {
        loop?.cancel()
        loop = Task { @MainActor [weak self] in
            var current = first
            while !Task.isCancelled {
                guard let self else { return }
                await self.play(current)
                current = OnboardingGesture(rawValue: current.rawValue + 1) ?? .hover
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
    }

    private func pause(_ seconds: Double) async -> Bool {
        try? await Task.sleep(for: .seconds(seconds))
        return !Task.isCancelled
    }

    private func set(_ animation: Animation?, _ change: () -> Void) {
        withAnimation(animation, change)
    }

    private func reset(for gesture: OnboardingGesture) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            self.gesture = gesture
            island = .closed
            showsShelfItem = false
            swipeOpens = true
            switch gesture {
            case .hover, .click:
                prop = .pointer
                propPosition = CGPoint(x: 0.22, y: 0.86)
            case .swipe:
                prop = .twoFingers
                propPosition = CGPoint(x: 0.5, y: 0.34)
            case .dropFiles:
                prop = .file
                propPosition = CGPoint(x: 0.14, y: 0.8)
            }
        }
    }

    private func play(_ gesture: OnboardingGesture) async {
        reset(for: gesture)
        guard await pause(0.5) else { return }
        switch gesture {
        case .hover:
            set(Self.propMove) { propPosition = CGPoint(x: 0.53, y: 0.1) }
            guard await pause(0.7) else { return }
            set(Self.hoverSpring) { island = .hovered }
            guard await pause(0.45) else { return }
            set(Self.openSpring) { island = .open }
            guard await pause(1.6) else { return }
            set(Self.propMove) { propPosition = CGPoint(x: 0.8, y: 0.9) }
            guard await pause(0.25) else { return }
            set(Self.closeSpring) { island = .closed }
        case .click:
            set(Self.propMove) { propPosition = CGPoint(x: 0.53, y: 0.1) }
            guard await pause(0.8) else { return }
            set(nil) { clickPulse += 1 }
            set(Self.openSpring) { island = .open }
            guard await pause(1.6) else { return }
            set(Self.propMove) { propPosition = CGPoint(x: 0.2, y: 0.9) }
            guard await pause(0.25) else { return }
            set(Self.closeSpring) { island = .closed }
        case .swipe:
            set(.smooth(duration: 0.5)) {
                propPosition = CGPoint(x: 0.5, y: 0.62)
                island = .stretched
            }
            guard await pause(0.5) else { return }
            set(Self.openSpring) { island = .open }
            guard await pause(1.4) else { return }
            set(nil) {
                swipeOpens = false
                propPosition = CGPoint(x: 0.5, y: 0.86)
            }
            set(.smooth(duration: 0.5)) { propPosition = CGPoint(x: 0.5, y: 0.6) }
            guard await pause(0.45) else { return }
            set(Self.closeSpring) { island = .closed }
        case .dropFiles:
            set(.easeInOut(duration: 0.9)) { propPosition = CGPoint(x: 0.5, y: 0.2) }
            guard await pause(0.6) else { return }
            set(Self.openSpring) { island = .open }
            guard await pause(0.5) else { return }
            set(.spring(response: 0.35, dampingFraction: 0.8)) {
                prop = .none
                showsShelfItem = true
            }
            guard await pause(1.4) else { return }
            set(Self.closeSpring) { island = .closed }
        }
        _ = await pause(0.9)
    }
}

/// The miniature: a dark display with the island at its top edge and the current prop.
struct OnboardingNotchDemo: View {
    @ObservedObject var model: OnboardingNotchDemoModel

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.13, green: 0.17, blue: 0.36), Color(red: 0.32, green: 0.16, blue: 0.4), Color(red: 0.12, green: 0.1, blue: 0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                island(in: size)

                propView
                    .position(x: model.propPosition.x * size.width, y: model.propPosition.y * size.height)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Demonstration: \(model.gesture.title). \(model.gesture.detail)")
    }

    private func islandSize(in size: CGSize) -> CGSize {
        switch model.island {
        case .closed: CGSize(width: 70, height: 15)
        case .hovered: CGSize(width: 76, height: 18)
        case .stretched: CGSize(width: 82, height: 24)
        case .open: CGSize(width: min(232, size.width - 40), height: 86)
        }
    }

    private func island(in size: CGSize) -> some View {
        let islandSize = islandSize(in: size)
        let isOpen = model.island == .open
        let radius: CGFloat = isOpen ? 16 : 6
        return UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius, style: .continuous)
            .fill(.black)
            .frame(width: islandSize.width, height: islandSize.height)
            .overlay(alignment: .top) {
                if isOpen {
                    openContent
                        .transition(.blurReplace)
                }
            }
            .shadow(color: .black.opacity(isOpen ? 0.5 : 0), radius: 6)
    }

    private var openContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                ForEach(["house.fill", "tray.fill", "timer"], id: \.self) { symbol in
                    Image(systemName: symbol)
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundStyle(symbol == (model.showsShelfItem ? "tray.fill" : "house.fill") ? Color.white : Color.gray)
                }
                Spacer()
                Circle().fill(Color(white: 0.16)).frame(width: 11, height: 11)
            }
            .frame(height: 12)

            if model.showsShelfItem {
                HStack(spacing: 8) {
                    VStack(spacing: 3) {
                        Image(systemName: "doc.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.white)
                        Capsule().fill(Color.gray.opacity(0.6)).frame(width: 26, height: 3)
                    }
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08)))
                    .transition(.scale.combined(with: .opacity))
                    Spacer()
                }
            } else {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(LinearGradient(colors: [.orange, .pink], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 4) {
                        Capsule().fill(Color.white.opacity(0.9)).frame(width: 64, height: 4)
                        Capsule().fill(Color.gray).frame(width: 44, height: 4)
                        Capsule().fill(Color.white.opacity(0.25)).frame(width: 90, height: 3).padding(.top, 6)
                    }
                    Spacer()
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 48, height: 40)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var propView: some View {
        switch model.prop {
        case .none:
            EmptyView()
        case .pointer:
            ZStack {
                OnboardingClickRipple(trigger: model.clickPulse)
                Image(systemName: "cursorarrow")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 1.5, y: 1)
                    .offset(x: 5, y: 7)
            }
        case .twoFingers:
            VStack(spacing: 2) {
                Image(systemName: model.swipeOpens ? "arrow.down" : "arrow.up")
                    .font(.system(size: 10, weight: .bold))
                HStack(spacing: 4) {
                    Circle().frame(width: 10, height: 10)
                    Circle().frame(width: 10, height: 10)
                }
            }
            .foregroundStyle(.white.opacity(0.85))
            .shadow(color: .black.opacity(0.4), radius: 2)
        case .file:
            Image(systemName: "doc.fill")
                .font(.system(size: 20))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                .transition(.scale(scale: 0.2).combined(with: .opacity))
        }
    }
}

/// A ring that expands and fades each time `trigger` changes.
struct OnboardingClickRipple: View {
    let trigger: Int
    @State private var expanded = true

    var body: some View {
        Circle()
            .stroke(Color.white.opacity(0.8), lineWidth: 1.5)
            .frame(width: 24, height: 24)
            .scaleEffect(expanded ? 1.4 : 0.3)
            .opacity(expanded ? 0 : 1)
            .onChange(of: trigger) { _, _ in
                var reset = Transaction()
                reset.disablesAnimations = true
                withTransaction(reset) { expanded = false }
                withAnimation(.easeOut(duration: 0.45)) { expanded = true }
            }
    }
}
