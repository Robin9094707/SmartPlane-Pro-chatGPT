import SwiftUI

extension View {
    @ViewBuilder func planeGlass() -> some View {
        if #available(iOS 26, *) { self.glassEffect(.regular, in: .rect(cornerRadius: 26)) }
        else { self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26)) }
    }
    func panel() -> some View { padding(20).background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 26)).overlay { RoundedRectangle(cornerRadius: 26).strokeBorder(.white.opacity(0.1)) } }
}
struct SkyBackground: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(colors: [Color(red: 0.025, green: 0.09, blue: 0.17), Color(red: 0.035, green: 0.17, blue: 0.23), Color(red: 0.03, green: 0.08, blue: 0.13)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle().fill(.mint.opacity(0.12)).frame(width: 450, height: 450).blur(radius: 100).offset(x: geo.size.width * 0.4, y: -180)
                Canvas { context, size in
                    for i in 0..<40 {
                        let x = CGFloat((i * 173 + 41) % 997) / 997 * size.width
                        let y = CGFloat((i * 97 + 13) % 491) / 491 * size.height
                        context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.5, height: 1.5)), with: .color(.white.opacity(0.18)))
                    }
                    var path = Path()
                    path.move(to: CGPoint(x: -60, y: size.height * 0.65))
                    path.addCurve(to: CGPoint(x: size.width + 70, y: size.height * 0.35), control1: CGPoint(x: size.width * 0.4, y: size.height * 0.3), control2: CGPoint(x: size.width * 0.6, y: size.height * 0.8))
                    context.stroke(path, with: .color(.mint.opacity(0.08)), style: StrokeStyle(lineWidth: 1, dash: [4, 8]))
                }
            }
        }.ignoresSafeArea()
    }
}
struct PlaneSilhouette: Shape {
    func path(in r: CGRect) -> Path {
        let points: [(CGFloat, CGFloat)] = [(0.5,0.04),(0.54,0.12),(0.55,0.35),(0.95,0.53),(0.98,0.64),(0.56,0.53),(0.54,0.80),(0.70,0.9),(0.70,0.96),(0.5,0.91),(0.30,0.96),(0.30,0.9),(0.46,0.80),(0.44,0.53),(0.02,0.64),(0.05,0.53),(0.45,0.35),(0.46,0.12)]
        var p = Path(); p.move(to: CGPoint(x: r.minX + points[0].0*r.width, y: r.minY + points[0].1*r.height))
        for (x,y) in points.dropFirst() { p.addLine(to: CGPoint(x: r.minX+x*r.width, y: r.minY+y*r.height)) }; p.closeSubpath(); return p
    }
}
struct StatusPill: View {
    var text: String
    var active: Bool
    var body: some View { HStack(spacing: 7) { Circle().fill(active ? .mint : .orange).frame(width: 6, height: 6); Text(text).font(.caption.weight(.semibold)) }.padding(.horizontal, 13).padding(.vertical, 9).planeGlass() }
}
struct Metric: View {
    let title: String; let value: String; let symbol: String
    var body: some View { VStack(alignment: .leading, spacing: 8) { Image(systemName: symbol).foregroundStyle(.mint); Text(value).font(.title3.bold().monospacedDigit()); Text(title).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading) }
}
