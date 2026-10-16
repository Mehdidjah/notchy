import Combine
import SwiftUI

/// Sizes of the download activity's wings in the host's three-column layout.
///
/// The columns are: left `h - 12`, black centre `notch + 40 (+ 58 with the rate)`, right
/// `max(60, h) (+ 58 with the rate)`, all centred on the notch. Worked through for a 32-pt
/// notch, the centre's right edge lands exactly on the notch's right edge and the 40 (+ 58) pt
/// widening sits entirely to the notch's left, balancing the narrow left column against the
/// wide right one. The host's centre is exactly the notch, so that widening belongs to the
/// left wing: left `h - 12 + 40 (+ 58)`, right `max(60, h) (+ 58)`. The island's total width
/// and centring are unchanged, so the arrow tile (leading) and the indicator (trailing) land
/// in the same place for any notch height.
///
/// The download view keeps its own hover and swipe state, which never changes, so these
/// widths ignore both.
enum DownloadWingMetrics {
    static let downloadingCenterExtra: CGFloat = 40
    static let speedAllowance: CGFloat = 58
    static let minimumRightWing: CGFloat = 60

    static func centerExtra(showsSpeed: Bool) -> CGFloat {
        downloadingCenterExtra + (showsSpeed ? speedAllowance : 0)
    }

    static func leftWidth(in context: ClosedActivityContext, showsSpeed: Bool) -> CGFloat {
        max(0, context.closedHeight - 12) + centerExtra(showsSpeed: showsSpeed)
    }

    static func rightWidth(in context: ClosedActivityContext, showsSpeed: Bool) -> CGFloat {
        max(minimumRightWing, context.closedHeight) + (showsSpeed ? speedAllowance : 0)
    }
}

/// "1.2 MB/s", in Finder's file-size units.
@MainActor
enum DownloadSpeedText {
    private static let formatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.isAdaptive = true
        return formatter
    }()

    static func string(bytesPerSecond: Double) -> String {
        formatter.string(fromByteCount: Int64(bytesPerSecond)) + "/s"
    }
}

/// What the download wings draw. Frozen while the activity closes so the checkmark (or the
/// bar) folds away with it instead of changing on the way out.
@MainActor
final class DownloadWingModel: ObservableObject {
    struct Display: Equatable {
        var isCompleted = false
        var speedText: String?
        var fraction: Double?
        var style: DownloadIndicatorStyle = .progress
    }

    @Published fileprivate(set) var display = Display()
}

/// A browser download on the closed notch: an accent-tinted
/// arrow tile on the left, an indicator on the right (linear bar or spinning ring, determinate
/// when the browser publishes progress), optionally preceded by the rate, and a green
/// checkmark for two seconds once the download lands.
@MainActor
final class DownloadActivity: ClosedLiveActivity {
    static let identifier = "download"

    let activityID = DownloadActivity.identifier
    let priority = ClosedActivityPriority.download
    weak var center: IslandActivityCenter?

    let wingModel = DownloadWingModel()
    private(set) var isDownloading = false
    private(set) var detectionEnabled = true
    private(set) var showsSpeed = false
    private let changes = PassthroughSubject<Void, Never>()
    private var cancellables: Set<AnyCancellable> = []

    private struct Snapshot {
        var isDownloading: Bool
        var isCompleted: Bool
        var bytesPerSecond: Double?
        var fraction: Double?
        var showSpeedSetting: Bool
        var style: DownloadIndicatorStyle
        var enabled: Bool
    }

    init(watcher: DownloadWatcher = .shared) {
        let settings = watcher.settings
        Publishers.CombineLatest4(
            watcher.$isDownloading,
            watcher.$isCompleted,
            watcher.$bytesPerSecond,
            watcher.$fractionCompleted
        )
        .combineLatest(settings.$showDownloadSpeed, settings.$indicatorStyle, settings.$enableDownloadDetection)
        .map { live, showSpeed, style, enabled in
            Snapshot(
                isDownloading: live.0,
                isCompleted: live.1,
                bytesPerSecond: live.2,
                fraction: live.3,
                showSpeedSetting: showSpeed,
                style: style,
                enabled: enabled
            )
        }
        .sink { [weak self] snapshot in self?.apply(snapshot) }
        .store(in: &cancellables)
    }

    var isActivityVisible: Bool { detectionEnabled && isDownloading }

    var activityDidChange: AnyPublisher<Void, Never> { changes.eraseToAnyPublisher() }

    func leftWingWidth(in context: ClosedActivityContext) -> CGFloat {
        DownloadWingMetrics.leftWidth(in: context, showsSpeed: showsSpeed)
    }

    func rightWingWidth(in context: ClosedActivityContext) -> CGFloat {
        DownloadWingMetrics.rightWidth(in: context, showsSpeed: showsSpeed)
    }

    func leftWing(in context: ClosedActivityContext) -> AnyView {
        AnyView(DownloadLeftWing(closedHeight: context.closedHeight))
    }

    func rightWing(in context: ClosedActivityContext) -> AnyView {
        AnyView(DownloadRightWing(model: wingModel))
    }

    private func apply(_ snapshot: Snapshot) {
        let wasVisible = isActivityVisible
        let hadSpeed = showsSpeed
        isDownloading = snapshot.isDownloading
        detectionEnabled = snapshot.enabled
        let speedText = snapshot.showSpeedSetting && !snapshot.isCompleted
            ? snapshot.bytesPerSecond.map(DownloadSpeedText.string(bytesPerSecond:))
            : nil
        showsSpeed = speedText != nil

        if snapshot.isDownloading {
            let display = DownloadWingModel.Display(
                isCompleted: snapshot.isCompleted,
                speedText: speedText,
                fraction: snapshot.isCompleted ? 1 : snapshot.fraction,
                style: snapshot.style
            )
            if display != wingModel.display { wingModel.display = display }
        }

        let visibilityChanged = wasVisible != isActivityVisible
        let widthChanged = hadSpeed != showsSpeed
        guard visibilityChanged || widthChanged else { return }
        if !visibilityChanged, isActivityVisible {
            // The rate appearing or leaving re-balances the wings over 0.25 s.
            withAnimation(.smooth(duration: 0.25)) { center?.reevaluate() }
        }
        changes.send()
    }
}

// MARK: - Wings

private struct DownloadLeftWing: View {
    let closedHeight: CGFloat

    var body: some View {
        let side = max(0, closedHeight - 12)
        HStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.accentColor.opacity(0.14))
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: side, height: side)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityHidden(true)
    }
}

private struct DownloadRightWing: View {
    @ObservedObject var model: DownloadWingModel

    var body: some View {
        let display = model.display
        HStack(spacing: 0) {
            if display.isCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.green)
                    .padding(.trailing, 6)
                    .transition(.opacity)
            } else {
                HStack(spacing: 6) {
                    if let speedText = display.speedText {
                        Text(speedText)
                            .font(.system(size: 10, weight: .medium).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .fixedSize()
                            .transition(.opacity)
                    }
                    indicator(display)
                }
                .padding(.trailing, 6)
                .animation(.smooth(duration: 0.2), value: display.speedText)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(display))
    }

    @ViewBuilder
    private func indicator(_ display: DownloadWingModel.Display) -> some View {
        switch display.style {
        case .circle:
            DownloadRing(fraction: display.fraction)
        case .progress:
            if let fraction = display.fraction {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .tint(.accentColor)
                    .frame(width: 40)
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(.accentColor)
                    .frame(width: 40)
            }
        }
    }

    private func accessibilityText(_ display: DownloadWingModel.Display) -> String {
        if display.isCompleted { return "Download finished" }
        var text = "Downloading"
        if let fraction = display.fraction { text += ", \(Int((fraction * 100).rounded())) percent" }
        if let speed = display.speedText { text += ", \(speed)" }
        return text
    }
}

/// The 16-pt ring: a grey track and an accent arc. Without known progress a quarter arc spins
/// once a second; with it, the arc fills clockwise from the top.
struct DownloadRing: View {
    let fraction: Double?
    @State private var isSpinning = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.3), lineWidth: 3.5)
            if let fraction {
                Circle()
                    .trim(from: 0, to: max(0.02, fraction))
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            } else {
                Circle()
                    .trim(from: 0, to: 0.25)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                    .rotationEffect(.degrees(isSpinning ? 360 : 0))
                    .onAppear {
                        withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                            isSpinning = true
                        }
                    }
            }
        }
        .frame(width: 16, height: 16)
    }
}
