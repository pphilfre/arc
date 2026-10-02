import SwiftUI
import SwiftData

struct ProfileSheet: View {
    @Bindable var model: ArcModel
    @Query(sort: \SavedPlace.savedAt, order: .reverse) private var saved: [SavedPlace]
    @Query(sort: \Journey.arrival, order: .reverse) private var journeys: [Journey]
    @Environment(\.modelContext) private var context
    @State private var page = 0
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Profile", selection: $page) {
                    Text("Places").tag(0); Text("Journeys").tag(1); Text("Settings").tag(2)
                }.pickerStyle(.segmented).padding(.horizontal, 20).padding(.bottom, 12)
                if page == 2 { SettingsForm(model: model) }
                else if page == 1 {
                    if journeys.isEmpty {
                        ContentUnavailableView("Your journeys", systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                            description: Text("Completed journeys appear here after you arrive and tap Finish."))
                    } else {
                        List {
                            ForEach(journeys) { journey in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(journey.destinationPlace?.name ?? "Journey").font(.headline)
                                    Text("From \(journey.startPlace?.name ?? "My Location")").font(.subheadline).foregroundStyle(.secondary)
                                    if !journey.stopPlaces.isEmpty {
                                        Text("Via \(journey.stopPlaces.map(\.name).joined(separator: ", "))").font(.caption).foregroundStyle(.secondary)
                                    }
                                    HStack {
                                        Text(model.preferences.units.distance(journey.distance))
                                        Text(duration(journey.duration)); Spacer()
                                        Text(journey.arrival, format: .dateTime.day().month().hour().minute())
                                    }.font(.caption).foregroundStyle(.secondary)
                                }.padding(.vertical, 6)
                            }.onDelete { offsets in
                                offsets.forEach { context.delete(journeys[$0]) }
                                try? context.save()
                            }
                        }
                    }
                } else {
                    List {
                        if !model.navigation.active {
                            Section {
                                Button(action: model.toggleMovement) {
                                    Label(model.location.isRecording ? "Finish movement session" : "Start movement session",
                                          systemImage: "speedometer")
                                }
                            }
                        }
                        Section("Saved places") {
                            if saved.isEmpty { Text("Save a place to keep it close.").foregroundStyle(.secondary) }
                            ForEach(saved) { item in
                                if let place = item.place {
                                    Button {
                                        model.showingProfile = false; model.selectedPlace = place
                                        model.command(.focus(place.coordinate))
                                    } label: {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(place.name).font(.headline).foregroundStyle(.primary)
                                            Text(place.address).font(.subheadline).foregroundStyle(.secondary)
                                        }.padding(.vertical, 4)
                                    }
                                }
                            }.onDelete { offsets in
                                offsets.forEach { context.delete(saved[$0]) }; try? context.save()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Arc").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { model.showingProfile = false } } }
        }
    }
}

struct SettingsForm: View {
    @Bindable var model: ArcModel
    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Appearance", selection: $model.preferences.appearance) {
                    ForEach(Appearance.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
                Picker("Accent", selection: $model.preferences.accent) {
                    ForEach(Accent.allCases) { Label($0.rawValue, systemImage: "circle.fill").foregroundStyle($0.color).tag($0) }
                }
            }
            Section("Map") {
                Picker("Map", selection: $model.preferences.satellite) { Text("Default").tag(false); Text("Satellite").tag(true) }
                Toggle("3D buildings", isOn: $model.preferences.buildings)
                Toggle("Traffic", isOn: $model.preferences.traffic)
                Toggle("Driving POIs", isOn: $model.preferences.drivingPOIs)
            }
            Section("Navigation") {
                Picker("Speed units", selection: $model.preferences.units) { ForEach(SpeedUnit.allCases) { Text($0.rawValue).tag($0) } }
                Picker("Voice guidance", selection: $model.preferences.voice) { ForEach(VoiceMode.allCases) { Text($0.rawValue).tag($0) } }
                Toggle("Avoid motorways", isOn: $model.preferences.avoidMotorways)
                Toggle("Avoid tolls", isOn: $model.preferences.avoidTolls)
                Toggle("Avoid ferries", isOn: $model.preferences.avoidFerries)
            }
            Section("Interactions") {
                Toggle("Haptics", isOn: $model.preferences.haptics)
                Picker("Haptic strength", selection: $model.preferences.hapticLevel) {
                    ForEach(HapticLevel.allCases) { Text($0.rawValue).tag($0) }
                }.disabled(!model.preferences.haptics)
            }
            Section {
                Text("Your saved places, searches and journey summaries stay on this iPhone. Arc doesn't save a continuous GPS history.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .onChange(of: model.preferences.hapticLevel) { _, _ in model.haptic.tap() }
    }
}

