import SwiftUI

struct LayersSheet: View {
    @Bindable var model: ArcModel
    var body: some View {
        @Bindable var preferences = model.preferences
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text("Layers").font(.title2.bold())
                Spacer()
                Button { model.showingLayers = false } label: { Image(systemName: "xmark") }.buttonStyle(.glass)
            }
            HStack(spacing: 12) {
                mapChoice("Default", symbol: "map.fill", satellite: false)
                mapChoice("Satellite", symbol: "globe.europe.africa.fill", satellite: true)
            }
            Toggle("3D", systemImage: "building.2.fill", isOn: $preferences.buildings)
            Toggle("Traffic", systemImage: "car.side.fill", isOn: $preferences.traffic)
            Toggle("Driving POIs", systemImage: "fuelpump.fill", isOn: $preferences.drivingPOIs)
        }.padding(26).padding(.top, 6)
        .onChange(of: model.preferences.buildings) { _, _ in model.haptic.tap(); model.command(.recenter) }
        .onChange(of: model.preferences.traffic) { _, _ in model.haptic.tap() }
        .onChange(of: model.preferences.drivingPOIs) { _, _ in model.haptic.tap() }
    }
    private func mapChoice(_ title: String, symbol: String, satellite: Bool) -> some View {
        Button {
            model.preferences.satellite = satellite; model.haptic.tap()
        } label: {
            VStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 30, weight: .medium))
                HStack {
                    Text(title).font(.subheadline.weight(.semibold))
                    if model.preferences.satellite == satellite { Image(systemName: "checkmark.circle.fill") }
                }
            }.frame(maxWidth: .infinity).padding(.vertical, 18)
                .glassEffect(.regular.tint(model.preferences.satellite == satellite ? model.preferences.accent.color.opacity(0.16) : .clear).interactive(), in: .rect(cornerRadius: 20))
        }.buttonStyle(.plain)
    }
}
