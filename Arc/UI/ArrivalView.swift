import SwiftUI

struct ArrivalView: View {
    @Bindable var model: ArcModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var particles = false
    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle().fill(.green.opacity(0.12)).frame(width: 80, height: 80)
                Image(systemName: "checkmark").font(.system(size: 38, weight: .bold))
                    .foregroundStyle(.green).symbolEffect(.bounce, value: appeared)
                    .scaleEffect(appeared ? 1 : 0.2).opacity(appeared ? 1 : 0)
            }.padding(.top, 8)
            VStack(spacing: 8) {
                Text("You've arrived").font(.system(.title2, design: .rounded, weight: .bold))
                Text(model.destination?.name ?? "Destination").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            Button(action: model.finishNavigation) { Text("Finish").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8) }
                .buttonStyle(.glassProminent).controlSize(.large)
        }.padding(28)
        .overlay {
            if particles && !reduceMotion { ArrivalParticles().allowsHitTesting(false) }
        }
        .task {
            if !reduceMotion {
                do { try await Task.sleep(for: .milliseconds(550)) } catch { return }
            }
            withAnimation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.65)) { appeared = true }
            model.haptic.tap(success: true)
            particles = true
            try? await Task.sleep(for: .seconds(2))
            particles = false
        }
    }
}

struct ArrivalParticles: View {
    @State private var start = Date()
    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let elapsed = timeline.date.timeIntervalSince(start)
                guard elapsed < 1.8 else { return }
                for index in 0..<22 {
                    let angle = Double(index) * 2.39996
                    let speed = 55 + Double(index % 5) * 12
                    let point = CGPoint(x: size.width / 2 + cos(angle) * speed * elapsed,
                        y: 65 + sin(angle) * speed * elapsed + elapsed * elapsed * 45)
                    context.opacity = max(0, 1 - elapsed / 1.8)
                    let rect = CGRect(x: point.x, y: point.y, width: 3, height: 5)
                    context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(index.isMultiple(of: 3) ? .green : .mint))
                }
            }
        }
    }
}
