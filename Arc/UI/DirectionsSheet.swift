import SwiftUI
import MapboxNavigationCore

struct DirectionsSheet: View {
    @Bindable var model: ArcModel
    var body: some View {
        @Bindable var preferences = model.preferences
        NavigationStack {
            List {
                Section {
                    Picker("Travel mode", selection: $model.mode) {
                        ForEach(TravelMode.allCases) { mode in Label(mode.rawValue, systemImage: mode.symbol).tag(mode) }
                    }.pickerStyle(.segmented).listRowBackground(Color.clear)
                    Button { model.openSearch(.origin) } label: {
                        Label(model.origin?.name ?? "My Location", systemImage: "location.circle")
                    }
                    if model.origin != nil {
                        Button("Use My Location") { model.origin = nil; model.location.request(); Task { await model.calculate() } }
                    }
                    ForEach(Array(model.stops.enumerated()), id: \.offset) { _, stop in Label(stop.name, systemImage: "circle") }
                        .onMove { source, destination in
                            model.stops.move(fromOffsets: source, toOffset: destination)
                            Task { await model.calculate() }
                        }
                        .onDelete { offsets in model.stops.remove(atOffsets: offsets); Task { await model.calculate() } }
                    if let destination = model.destination { Label(destination.name, systemImage: "mappin.circle.fill") }
                    Button { model.openSearch(.stop) } label: { Label("Add stop", systemImage: "plus.circle") }
                }
                Section {
                    if model.navigation.calculating { ProgressView("Finding the best route…") }
                    if let error = model.navigation.error {
                        Text(error).foregroundStyle(.secondary)
                        Button("Try again") { Task { await model.calculate() } }
                    }
                    if let routes = model.navigation.routes {
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(duration(routes.mainRoute.route.expectedTravelTime)).font(.title.bold())
                                Text("\(model.preferences.units.distance(routes.mainRoute.route.distance)) · Arrive \(Date().addingTimeInterval(routes.mainRoute.route.expectedTravelTime).formatted(date: .omitted, time: .shortened))")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(action: model.startNavigation) { Text("Go").font(.title3.bold()).padding(.horizontal, 12) }
                                .buttonStyle(.glassProminent).controlSize(.large)
                        }.padding(.vertical, 6)
                        ForEach(Array(routes.alternativeRoutes.enumerated()), id: \.offset) { _, alternative in
                            Button {
                                model.haptic.tap()
                                Task { await model.navigation.select(alternative) }
                            } label: {
                                HStack {
                                    Label(duration(alternative.route.expectedTravelTime), systemImage: "arrow.triangle.branch")
                                    Spacer()
                                    Text(model.preferences.units.distance(alternative.route.distance)).foregroundStyle(.secondary)
                                }
                            }
                        }
                        Button { model.command(.overview) } label: { Label("Route overview", systemImage: "arrow.up.left.and.arrow.down.right") }
                    }
                }
                if model.mode == .driving {
                    Section("Route options") {
                        Toggle("Avoid motorways", isOn: $preferences.avoidMotorways)
                        Toggle("Avoid tolls", isOn: $preferences.avoidTolls)
                        Toggle("Avoid ferries", isOn: $preferences.avoidFerries)
                    }
                }
            }
            .navigationTitle("Directions").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Close") { model.cancelPlanning() } }
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
            }
        }
        .task(id: routeOptions) { await model.calculate() }
    }
    private var routeOptions: String {
        "\(model.mode)-\(model.preferences.avoidMotorways)-\(model.preferences.avoidTolls)-\(model.preferences.avoidFerries)"
    }
}

func duration(_ seconds: TimeInterval) -> String {
    let minutes = max(1, Int((seconds / 60).rounded()))
    return minutes < 60 ? "\(minutes) min" : "\(minutes / 60) hr \(minutes % 60) min"
}
