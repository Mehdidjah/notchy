import SwiftUI

/// The welcome page's stage light, drawn with shapes in place of Atoll's "spotlight" artwork.
///
/// Same proportions and tones as Atoll's: a 689 x 1005 canvas (so, fitted to the 400-pt window,
/// it runs the full height and the welcome stack sits in the middle of the beam); a beam that
/// starts 38 % wide at the top edge and widens to the full width at 92 % of the height, its foot
/// cut by the top half of the stage ellipse; grey shading that darkens downwards with a soft
/// left-to-right sheen; the stage ellipse below it. The beam is drawn at 30 % opacity, the stage
/// at 27 %, both softly blurred.
struct OnboardingSpotlight: View {
    /// Width / height of the artwork.
    static let aspectRatio: CGFloat = 689.0 / 1005.0

    var body: some View {
        GeometryReader { proxy in
            let unit = proxy.size.width / 689
            ZStack(alignment: .topLeading) {
                ZStack {
                    OnboardingSpotlightBeam()
                        .fill(
                            LinearGradient(
                                colors: [Color(white: 0.843), Color(white: 0.145)],
                                startPoint: UnitPoint(x: 0.5, y: 0),
                                endPoint: UnitPoint(x: 0.5, y: 0.92)
                            )
                        )
                    OnboardingSpotlightBeam()
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: .white.opacity(0), location: 0),
                                    .init(color: .white.opacity(0.21), location: 0.24),
                                    .init(color: Color(white: 0.149).opacity(0.366), location: 0.53),
                                    .init(color: Color(white: 0.18).opacity(0.69), location: 1)
                                ],
                                startPoint: UnitPoint(x: 0.21, y: 0.34),
                                endPoint: UnitPoint(x: 0.82, y: 0.36)
                            )
                        )
                }
                .opacity(0.3)
                .blur(radius: 2.5 * unit)

                Ellipse()
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.882), Color(white: 0.231)],
                            startPoint: UnitPoint(x: -0.84, y: 1.2),
                            endPoint: UnitPoint(x: -0.34, y: 1.57)
                        )
                    )
                    .frame(width: 679 * unit, height: 149 * unit)
                    .offset(x: 5 * unit, y: 851 * unit)
                    .opacity(0.27)
                    .blur(radius: 2.5 * unit)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .aspectRatio(Self.aspectRatio, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// The beam: a trapezoid from the top edge to the stage, whose foot is the upper half of the
/// stage ellipse, so the light seems to land on it.
struct OnboardingSpotlightBeam: Shape {
    func path(in rect: CGRect) -> Path {
        let unitX = rect.width / 689
        let unitY = rect.height / 1005
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * unitX, y: rect.minY + y * unitY)
        }
        // Stage ellipse the foot follows: centre (344.5, 923.5), radii 339.3 x 71.7.
        let centre = (x: CGFloat(344.5), y: CGFloat(923.5))
        let radius = (x: CGFloat(339.3), y: CGFloat(71.7))
        let kappa: CGFloat = 0.5523

        var path = Path()
        path.move(to: point(218.5, -4))
        path.addLine(to: point(481.5, -4))
        path.addLine(to: point(684, 923.5))
        // Right quarter of the ellipse top, then the left quarter.
        path.addCurve(
            to: point(centre.x, centre.y - radius.y),
            control1: point(centre.x + radius.x, centre.y - radius.y * kappa),
            control2: point(centre.x + radius.x * kappa, centre.y - radius.y)
        )
        path.addCurve(
            to: point(centre.x - radius.x, centre.y),
            control1: point(centre.x - radius.x * kappa, centre.y - radius.y),
            control2: point(centre.x - radius.x, centre.y - radius.y * kappa)
        )
        path.addLine(to: point(5, 923.5))
        path.closeSubpath()
        return path
    }
}

/// Notchy's mark: a dark squircle "display" whose top edge carries the black island,
/// over a wallpaper in the hello gradient's colours.
///
/// Drawn on the macOS app-icon grid like Atoll's "logo2" (a 1024-px app icon): in a frame of
/// `size` the squircle is 80.5 % wide (824 of 1024) with a 22.5 % continuous corner radius and
/// the usual soft icon shadow, so it occupies the same space on the welcome page.
struct OnboardingAppGlyph: View {
    var size: CGFloat = 100

    /// Share of the frame the icon's squircle covers on the macOS icon grid.
    static let gridFill: CGFloat = 824.0 / 1024.0

    var body: some View {
        let side = size * Self.gridFill
        let scale = side / 100
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 22.5 * scale, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.22), Color(white: 0.05)], startPoint: .top, endPoint: .bottom))

            RoundedRectangle(cornerRadius: 13 * scale, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.16, green: 0.32, blue: 0.95),
                            Color(red: 0.55, green: 0.26, blue: 0.92),
                            Color(red: 0.98, green: 0.36, blue: 0.62)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 13 * scale, style: .continuous)
                        .fill(RadialGradient(colors: [.white.opacity(0.28), .clear], center: .bottomLeading, startRadius: 0, endRadius: 70 * scale))
                }
                .padding(9 * scale)

            UnevenRoundedRectangle(
                bottomLeadingRadius: 7 * scale,
                bottomTrailingRadius: 7 * scale,
                style: .continuous
            )
            .fill(.black)
            .frame(width: 46 * scale, height: 14 * scale)
            .overlay(alignment: .trailing) {
                Circle()
                    .fill(Color(white: 0.22))
                    .frame(width: 4 * scale, height: 4 * scale)
                    .padding(.trailing, 9 * scale)
            }
            .padding(.top, 9 * scale)

            RoundedRectangle(cornerRadius: 22.5 * scale, style: .continuous)
                .fill(LinearGradient(colors: [.white.opacity(0.14), .clear], startPoint: .top, endPoint: .center))
                .allowsHitTesting(false)
        }
        .frame(width: side, height: side)
        .overlay {
            RoundedRectangle(cornerRadius: 22.5 * scale, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 1)
        }
        // macOS icon shadow: 10/1024 blur, 10/1024 drop, 30 % black.
        .shadow(color: .black.opacity(0.3), radius: size * 10 / 1024, y: size * 10 / 1024)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The wordmark standing on the stage at the bottom of the welcome page: white condensed
/// heavy capitals 22 pt tall, about 112 pt wide, like Atoll's "ebullioscopic" image. The page
/// lays it out with an overlay blend.
struct OnboardingWordmark: View {
    static let height: CGFloat = 22

    var body: some View {
        Text("NOTCHISLAND")
            .font(.system(size: 29, weight: .heavy).width(.compressed))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(height: Self.height)
            .accessibilityHidden(true)
    }
}
