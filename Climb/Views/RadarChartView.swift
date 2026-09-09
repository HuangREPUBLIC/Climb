import SwiftUI

/// Generic N-axis radar/spider chart comparing two datasets, used by
/// PlayerMatchupView to visualize the linked player vs a chosen opponent.
struct RadarChartView: View {
    struct Axis: Identifiable {
        let id = UUID()
        let label: String
        /// Raw values; normalized per-axis against their own max so the
        /// larger of the two always reaches the outer ring, matching the
        /// reference app's comparison style.
        let primaryValue: Double
        let secondaryValue: Double
    }

    let axes: [Axis]
    var primaryColor: Color = .orange
    var secondaryColor: Color = .cyan
    var ringCount: Int = 4

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = size / 2 * 0.62

            ZStack {
                gridRings(center: center, radius: radius)
                axisLines(center: center, radius: radius)
                polygon(center: center, radius: radius, keyPath: \.secondaryValue)
                    .fill(secondaryColor.opacity(0.25))
                polygon(center: center, radius: radius, keyPath: \.secondaryValue)
                    .stroke(secondaryColor, lineWidth: 1.5)
                polygon(center: center, radius: radius, keyPath: \.primaryValue)
                    .fill(primaryColor.opacity(0.25))
                polygon(center: center, radius: radius, keyPath: \.primaryValue)
                    .stroke(primaryColor, lineWidth: 1.5)
                labels(center: center, radius: radius)
            }
        }
    }

    private var axisCount: Int { max(axes.count, 3) }

    private func point(forFraction fraction: Double, index: Int, center: CGPoint, radius: CGFloat) -> CGPoint {
        let angle = angle(for: index)
        let clamped = max(0, min(fraction, 1))
        return CGPoint(
            x: center.x + radius * CGFloat(clamped) * cos(angle),
            y: center.y + radius * CGFloat(clamped) * sin(angle)
        )
    }

    private func angle(for index: Int) -> CGFloat {
        // Start at the top (-90°) and go clockwise.
        (2 * .pi / CGFloat(axisCount)) * CGFloat(index) - .pi / 2
    }

    private func normalizedFraction(_ value: Double, against other: Double) -> Double {
        let maxValue = max(value, other, 0.0001)
        return value / maxValue
    }

    private func polygon(center: CGPoint, radius: CGFloat, keyPath: KeyPath<Axis, Double>) -> Path {
        var path = Path()
        for (index, axis) in axes.enumerated() {
            let other = keyPath == \Axis.primaryValue ? axis.secondaryValue : axis.primaryValue
            let fraction = normalizedFraction(axis[keyPath: keyPath], against: other)
            let point = point(forFraction: fraction, index: index, center: center, radius: radius)
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }

    private func gridRings(center: CGPoint, radius: CGFloat) -> some View {
        ForEach(1...ringCount, id: \.self) { ring in
            let fraction = Double(ring) / Double(ringCount)
            Path { path in
                for index in 0..<axisCount {
                    let point = point(forFraction: fraction, index: index, center: center, radius: radius)
                    if index == 0 {
                        path.move(to: point)
                    } else {
                        path.addLine(to: point)
                    }
                }
                path.closeSubpath()
            }
            .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        }
    }

    private func axisLines(center: CGPoint, radius: CGFloat) -> some View {
        ForEach(0..<axisCount, id: \.self) { index in
            Path { path in
                path.move(to: center)
                path.addLine(to: point(forFraction: 1, index: index, center: center, radius: radius))
            }
            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        }
    }

    private func labels(center: CGPoint, radius: CGFloat) -> some View {
        ForEach(Array(axes.enumerated()), id: \.offset) { index, axis in
            let labelPoint = point(forFraction: 1.28, index: index, center: center, radius: radius)
            Text(axis.label)
                .scaledFont(10)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .position(labelPoint)
        }
    }
}
