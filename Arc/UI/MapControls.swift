import SwiftUI

/// One control family for browsing, camera following and current speed.
struct CircularMapControl<Content: View>: View {
    var tint: Color = .clear
    let label: String
    let action: () -> Void
    @ViewBuilder let content: () -> Content
    var body: some View {
        Button(action: action) {
            content().frame(width: 58, height: 58, alignment: .center).contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(tint).interactive(), in: .circle)
        .accessibilityLabel(label)
    }
}

struct SpeedLimitRoundel: View {
    let value: Int?
    var body: some View {
        Text(value.map(String.init) ?? "–")
            .font(.system(size: 19, weight: .bold, design: .rounded)).monospacedDigit()
            .foregroundStyle(.white).shadow(color: .black.opacity(0.45), radius: 2)
            .frame(width: 44, height: 44)
            .overlay { Circle().strokeBorder(.red, lineWidth: 3.5) }
            .accessibilityLabel(value.map { "Speed limit \($0)" } ?? "Speed limit unavailable")
    }
}

struct CurrentSpeedControl: View {
    @Bindable var model: ArcModel
    @Binding var expanded: Bool
    private var overLimit: Bool { model.navigation.speedLimit.map { model.navigation.speed > $0 } ?? false }
    var body: some View {
        CircularMapControl(tint: overLimit ? .red.opacity(0.3) : .clear,
            label: "Current speed \(model.preferences.units.speed(model.navigation.speed)) \(model.preferences.units.rawValue). Show movement", action: {
                expanded.toggle(); model.haptic.tap()
            }) {
                VStack(spacing: 0) {
                    Text(model.preferences.units.speed(model.navigation.speed).description)
                        .font(.system(size: 25, weight: .semibold, design: .rounded)).monospacedDigit()
                        .contentTransition(.numericText())
                    Text(model.preferences.units.rawValue).font(.system(size: 10, weight: .medium))
                }
            }
        .contextMenu {
            ForEach(SpeedUnit.allCases) { unit in
                Button(unit.rawValue) { model.preferences.units = unit; model.haptic.tap() }
            }
        }
    }
}
