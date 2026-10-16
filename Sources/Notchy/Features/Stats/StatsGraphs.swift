import SwiftUI

/// Pure geometry for the card graphs, kept apart from the views so it can be tested.
enum StatsGraphGeometry {
    /// Scales values to 0...1 against the window maximum (not a fixed 100), so a quiet graph
    /// still shows its shape. All zeros stay zeros.
    static func normalized(_ values: [Double], maximum: Double? = nil) -> [Double] {
        let peak = maximum ?? values.max() ?? 0
        guard peak > 0 else { return values.map { _ in 0 } }
        return values.map { min(1, max(0, $0 / peak)) }
    }

    /// Points for a line from the left edge to the right edge. `baseline` is where zero sits
    /// and `amplitude` how far (signed, in points) a full value moves away from it.
    static func points(for normalized: [Double], width: CGFloat, baseline: CGFloat, amplitude: CGFloat) -> [CGPoint] {
        guard !normalized.isEmpty else { return [] }
        let step = normalized.count > 1 ? width / CGFloat(normalized.count - 1) : 0
        return normalized.enumerated().map { index, value in
            CGPoint(x: CGFloat(index) * step, y: baseline - amplitude * CGFloat(value))
        }
    }

    static func line(through points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        return path
    }

    /// The line closed back along the baseline so it can be filled.
    static func area(under points: [CGPoint], baseline: CGFloat) -> Path {
        var path = Path()
        guard let first = points.first, let last = points.last else { return path }
        path.move(to: CGPoint(x: first.x, y: baseline))
        for point in points {
            path.addLine(to: point)
        }
        path.addLine(to: CGPoint(x: last.x, y: baseline))
        path.closeSubpath()
        return path
    }
}

/// A single series: a 2-pt line over a soft gradient area, auto-scaled to the window maximum.
struct StatsSparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            let normalized = StatsGraphGeometry.normalized(values)
            let points = StatsGraphGeometry.points(
                for: normalized, width: proxy.size.width, baseline: height, amplitude: height
            )
            StatsGraphGeometry.area(under: points, baseline: height)
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0.3), color.opacity(0.1)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            StatsGraphGeometry.line(through: points)
                .stroke(color, lineWidth: 2)
        }
    }
}

/// Two series mirrored around a centre line (download/read above, upload/write below),
/// sharing one scale so the two halves stay comparable.
struct StatsMirroredGraph: View {
    let upperValues: [Double]
    let lowerValues: [Double]
    let upperColor: Color
    let lowerColor: Color

    var body: some View {
        GeometryReader { proxy in
            let centre = proxy.size.height / 2
            let peak = max(upperValues.max() ?? 0, lowerValues.max() ?? 0)
            let upper = StatsGraphGeometry.points(
                for: StatsGraphGeometry.normalized(upperValues, maximum: peak),
                width: proxy.size.width, baseline: centre, amplitude: centre
            )
            let lower = StatsGraphGeometry.points(
                for: StatsGraphGeometry.normalized(lowerValues, maximum: peak),
                width: proxy.size.width, baseline: centre, amplitude: -centre
            )

            Path { path in
                path.move(to: CGPoint(x: 0, y: centre))
                path.addLine(to: CGPoint(x: proxy.size.width, y: centre))
            }
            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)

            StatsGraphGeometry.area(under: upper, baseline: centre)
                .fill(
                    LinearGradient(
                        colors: [upperColor.opacity(0.3), upperColor.opacity(0.1)],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
            StatsGraphGeometry.line(through: upper)
                .stroke(upperColor, lineWidth: 2)

            StatsGraphGeometry.area(under: lower, baseline: centre)
                .fill(
                    LinearGradient(
                        colors: [lowerColor.opacity(0.3), lowerColor.opacity(0.1)],
                        startPoint: .bottom,
                        endPoint: .center
                    )
                )
            StatsGraphGeometry.line(through: lower)
                .stroke(lowerColor, lineWidth: 2)
        }
    }
}
