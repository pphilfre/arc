import SwiftUI

struct GuidanceView: View {
    @Bindable var model: ArcModel
    var body: some View {
        let guidance = model.navigation.guidance
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 18) {
                if guidance.exit != nil {
                    RoundaboutGlyph(angle: guidance.roundaboutAngle).frame(width: 48, height: 54)
                } else {
                    Image(systemName: guidance.symbol).font(.system(size: 38, weight: .semibold)).frame(width: 48)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.preferences.units.distance(guidance.turnDistance)).font(.title2.bold()).monospacedDigit()
                    Text(guidance.instruction).font(.headline).lineLimit(3)
                    if let junction = guidance.junction {
                        Text("Junction \(junction)").font(.caption.weight(.semibold))
                    }
                }
                Spacer(minLength: 0)
                if model.navigation.rerouting { DottedSpinner().frame(width: 26, height: 26).accessibilityLabel("Rerouting") }
            }
            if !guidance.lanes.isEmpty {
                HStack(spacing: 18) {
                    ForEach(guidance.lanes) { lane in
                        Image(systemName: lane.symbol).font(.title3.bold())
                            .foregroundStyle(lane.usable ? model.preferences.accent.color : Color.secondary.opacity(0.4))
                            .accessibilityLabel(lane.usable ? "Use this lane" : "Other lane")
                    }
                }.frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            if !guidance.following.isEmpty {
                Divider()
                Text("Then \(guidance.following)").font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }
        }.padding(20).glassEffect(.regular, in: .rect(cornerRadius: 28))
        .accessibilityElement(children: .combine)
    }
}

struct JourneyStatusView: View {
    @Bindable var model: ArcModel
    let end: () -> Void
    var body: some View {
        @Bindable var preferences = model.preferences
        VStack(spacing: 0) {
            GeometryReader { geometry in
                Capsule().fill(model.preferences.accent.color)
                    .frame(width: geometry.size.width * min(1, max(0, model.navigation.guidance.fraction)))
            }.frame(height: 2).padding(.horizontal, 20)
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(duration(model.navigation.guidance.remainingTime)).font(.title2.bold()).monospacedDigit()
                    HStack(spacing: 12) {
                        Text(model.preferences.units.distance(model.navigation.guidance.remainingDistance))
                        Text(model.navigation.guidance.arrival, style: .time)
                    }.font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer(minLength: 0)
                Menu {
                    Picker("Voice guidance", selection: $preferences.voice) {
                        ForEach(VoiceMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Button("Overview", systemImage: "arrow.up.left.and.arrow.down.right") { model.command(.overview) }
                    Button("Layers", systemImage: "square.3.layers.3d") { model.showingLayers = true }
                    Button("Settings", systemImage: "gearshape") { model.showingProfile = true }
                } label: {
                    Image(systemName: model.preferences.voice == .muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .frame(width: 36, height: 40)
                }.accessibilityLabel("Navigation options")
                Button("End", action: end).font(.headline).foregroundStyle(.red).buttonStyle(.glass)
            }.padding(20)
        }
    }
}

struct SpeedPill: View {
    @Bindable var model: ArcModel
    @Binding var expanded: Bool
    private var overLimit: Bool {
        guard let limit = model.navigation.speedLimit else { return false }
        return limit > 0 && model.navigation.speed > limit
    }
    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().strokeBorder(.red, lineWidth: 4).frame(width: 50, height: 50)
                if let limit = model.navigation.speedLimit {
                    Text(model.preferences.units.speed(limit).description).font(.system(size: 21, weight: .bold, design: .rounded))
                        .foregroundStyle(.white).shadow(color: .black.opacity(0.45), radius: 2)
                } else {
                    Text("–").font(.title2.bold()).foregroundStyle(.white).shadow(color: .black.opacity(0.45), radius: 2)
                }
            }
            Text(model.preferences.units.speed(model.navigation.speed).description)
                .font(.system(size: 29, weight: .semibold, design: .rounded)).monospacedDigit()
                .contentTransition(.numericText())
            Button {
                model.preferences.units = model.preferences.units == .mph ? .kmh : .mph
                model.haptic.tap()
            } label: { Text(model.preferences.units.rawValue).font(.caption.weight(.medium)) }
            Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.caption2.bold()).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10).padding(.vertical, 12)
        .glassEffect(.regular.tint(overLimit ? Color.red.opacity(0.35) : Color.clear).interactive(), in: .capsule)
        .onTapGesture { expanded.toggle(); model.haptic.tap() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Speed")
    }
}

struct MovementView: View {
    @Bindable var model: ArcModel
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            VStack(spacing: 18) {
                HStack {
                    Text(model.location.isRecording ? "Movement" : "Current movement").font(.headline)
                    Spacer()
                    if !model.navigation.active {
                        Button(model.location.isRecording ? "Finish" : "Start session", action: model.toggleMovement)
                            .font(.subheadline.weight(.semibold))
                    }
                }
                HStack(alignment: .firstTextBaseline) {
                    movementStat("Speed", value: "\(model.preferences.units.speed(model.navigation.speed)) \(model.preferences.units.rawValue)")
                    Spacer()
                    movementStat("Average", value: average)
                    Spacer()
                    movementStat("Distance", value: model.navigation.active ? model.preferences.units.distance(model.navigation.traveledDistance) : model.location.isRecording ? model.preferences.units.distance(model.location.session.distance) : "–")
                }
                HStack {
                    if model.location.isRecording || model.navigation.active {
                        Label { Text(model.navigation.active ? model.navigation.startedAt ?? .now : model.location.session.startedAt, style: .timer).monospacedDigit() } icon: { Image(systemName: "timer") }
                    }
                    Spacer()
                    if let fix = model.location.location, fix.verticalAccuracy >= 0 {
                        Label("\(Int(fix.altitude.rounded())) m", systemImage: "mountain.2").monospacedDigit()
                    }
                }.font(.caption).foregroundStyle(.secondary)
            }.padding(20).glassEffect(.regular, in: .rect(cornerRadius: 26))
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }
    private var average: String {
        if model.navigation.active, let start = model.navigation.startedAt {
            let speed = model.navigation.traveledDistance / max(1, Date().timeIntervalSince(start))
            return "\(model.preferences.units.speed(speed)) \(model.preferences.units.rawValue)"
        }
        return model.location.isRecording ? "\(model.preferences.units.speed(model.location.session.averageSpeed)) \(model.preferences.units.rawValue)" : "–"
    }
    private func movementStat(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value).font(.system(.headline, design: .rounded)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct DottedSpinner: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spinning = false
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(0..<10) { index in
                    Circle().fill(Color.primary.opacity(Double(index + 1) / 10))
                        .frame(width: 3, height: 3)
                        .offset(y: -geometry.size.width / 2 + 3)
                        .rotationEffect(.degrees(Double(index) * 36))
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .rotationEffect(.degrees(spinning ? 360 : 0))
        }
        .onAppear {
            if !reduceMotion {
                withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) { spinning = true }
            }
        }
    }
}

struct RoundaboutGlyph: View {
    let angle: Double
    var body: some View {
        ZStack {
            Circle().stroke(.secondary.opacity(0.4), lineWidth: 4).frame(width: 30, height: 30)
            Circle().trim(from: 0, to: max(0.15, min(0.95, angle / 360)))
                .stroke(.tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .frame(width: 30, height: 30).rotationEffect(.degrees(90))
            Image(systemName: "arrow.up").font(.headline.bold()).offset(y: -22).rotationEffect(.degrees(angle))
        }.accessibilityLabel("Roundabout exit")
    }
}
