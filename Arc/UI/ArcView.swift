import SwiftUI
import SwiftData

struct ArcView: View {
    @Bindable var model: ArcModel
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var glass
    @State private var showMovement = false
    @State private var ending = false
    private enum AlertKind { case notice, fasterRoute, endJourney }
    private var alertKind: AlertKind? {
        if model.notice != nil { return .notice }
        if model.navigation.fasterRouteDescription != nil { return .fasterRoute }
        return ending ? .endJourney : nil
    }
    private var alertTitle: String {
        switch alertKind {
        case .fasterRoute: "Faster route"
        case .endJourney: "End this journey?"
        default: "Arc"
        }
    }
    private var alertMessage: String {
        switch alertKind {
        case .notice: model.notice ?? ""
        case .fasterRoute: model.navigation.fasterRouteDescription ?? ""
        case .endJourney: "Journey history is saved when you arrive and press Finish."
        case nil: ""
        }
    }
    private var alertPresented: Binding<Bool> {
        let kind = alertKind
        return Binding(get: { alertKind != nil }, set: { if !$0 {
            switch kind {
            case .notice: model.notice = nil
            case .fasterRoute: model.navigation.resolveFasterRoute(false)
            case .endJourney: ending = false
            case nil: break
            }
        } })
    }

    private var panelPresented: Binding<Bool> {
        Binding(get: {
            !model.searching && (model.showingProfile || model.showingLayers || model.planning || model.selectedPlace != nil)
        }, set: { if !$0 {
            if model.searching { return }
            if model.showingProfile { model.showingProfile = false }
            else if model.showingLayers { model.showingLayers = false }
            else if model.planning { model.cancelPlanning() }
            else { model.dismissPlace() }
        } })
    }
    private var detents: Set<PresentationDetent> {
        if model.showingLayers { return [.height(360)] }
        if model.showingProfile { return [.large] }
        if model.planning { return [.height(450), .large] }
        return [.height(330), .fraction(0.75), .large]
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ArcMapView(model: model, colorScheme: scheme, presentation: MapPresentation(model: model)).ignoresSafeArea()
                GlassEffectContainer(spacing: 14) {
                    VStack(spacing: 16) {
                        if model.navigation.active && !model.navigation.arrived {
                            GuidanceView(model: model)
                        }
                        HStack(alignment: .top) {
                            if abs(model.bearing) > 4 && abs(model.bearing - 360) > 4 {
                                Button { model.command(.north); model.haptic.tap() } label: {
                                    Image(systemName: "location.north.fill")
                                        .foregroundStyle(.red).rotationEffect(.degrees(-model.bearing))
                                        .animation(.linear(duration: 0.1), value: model.bearing)
                                        .frame(width: 46, height: 46)
                                }
                                .glassEffect(.regular.interactive(), in: .circle)
                                .accessibilityLabel("Point north")
                            }
                            Spacer()
                            if !model.navigation.active && (model.navigation.speed > 1.4 || model.location.isRecording) {
                                SpeedPill(model: model, expanded: $showMovement)
                            }
                        }
                        if showMovement { MovementView(model: model) }
                        if let error = model.navigation.error ?? model.location.error {
                            Text(error).font(.footnote).padding(14)
                                .glassEffect(.regular, in: .rect(cornerRadius: 18))
                        }
                        Spacer(minLength: 0)
                        if !model.navigation.arrived {
                            HStack {
                                if model.navigation.active {
                                    CurrentSpeedControl(model: model, expanded: $showMovement)
                                }
                                Spacer()
                                if !model.following || !model.location.authorized {
                                    CircularMapControl(tint: model.navigation.active ? model.preferences.accent.color.opacity(0.16) : .clear,
                                        label: model.navigation.active ? "Follow navigation camera" : "Recenter on my location", action: model.recenter) {
                                            Image(systemName: model.navigation.active ? "location.north.line.fill" : "location.fill")
                                                .font(.system(size: 22, weight: .medium)).offset(x: -0.5, y: 0.5)
                                        }
                                }
                            }
                        }
                        if model.navigation.active && !model.navigation.arrived {
                            JourneyStatusView(model: model, end: { ending = true })
                        } else if !model.navigation.arrived {
                            browseControls
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 16)

                    if model.navigation.arrived {
                        ArrivalView(model: model)
                            .frame(width: min(geometry.size.width - 48, 360))
                            .glassEffect(.regular, in: .rect(cornerRadius: 36))
                            .glassEffectID("journey", in: glass)
                            .glassEffectTransition(.matchedGeometry)
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if model.searching {
                    SearchSheet(model: model)
                        .accessibilityIdentifier("search.surface")
                        .frame(height: geometry.size.height * 0.75)
                        .glassEffect(.regular, in: .rect(cornerRadius: 32))
                        .padding(.horizontal, 8).padding(.bottom, 6)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(10)
                }
            }
            .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.9), value: model.searching)
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.65, dampingFraction: 0.82), value: model.navigation.arrived)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showMovement)
        }
        .ignoresSafeArea(.keyboard)
        .sheet(isPresented: panelPresented) {
            Group {
                if model.showingProfile { ProfileSheet(model: model) }
                else if model.showingLayers { LayersSheet(model: model) }
                else if model.planning { DirectionsSheet(model: model) }
                else if let place = model.selectedPlace { PlaceSheet(model: model, place: place) }
            }
            .presentationDetents(detents)
            .presentationBackground(.regularMaterial)
            .presentationDragIndicator(.visible)
            .presentationBackgroundInteraction(model.showingProfile ? .disabled : .enabled)
            .presentationCornerRadius(32)
        }
        .alert(alertTitle, isPresented: alertPresented) {
            switch alertKind {
            case .notice:
                Button("OK") { model.notice = nil }
            case .fasterRoute:
                Button("Keep current route", role: .cancel) { model.navigation.resolveFasterRoute(false) }
                Button("Switch route") { model.navigation.resolveFasterRoute(true) }
            case .endJourney:
                Button("Keep navigating", role: .cancel) { ending = false }
                Button("End journey", role: .destructive) { ending = false; model.finishNavigation() }
            case nil: EmptyView()
            }
        } message: { Text(alertMessage) }
        .task { model.context = context }
        .onChange(of: scenePhase) { _, phase in
            model.location.foreground(phase == .active)
            model.navigation.foreground(phase == .active)
        }
        .onChange(of: model.location.authorized) { _, authorized in
            if authorized {
                model.navigation.beginFreeDrive(); model.command(.recenter)
                if model.planning { Task { await model.calculate() } }
            }
        }
        .onChange(of: model.navigation.guidance.instruction) { _, _ in
            if model.navigation.active { model.liveActivity.update(model.activityState) }
        }
        .onChange(of: model.preferences.drivingPOIs) { _, enabled in
            if enabled { model.refreshDrivingPlaces() }
        }
        .onChange(of: model.preferences.voice) { _, _ in model.navigation.voiceModeChanged() }
    }

    private var browseControls: some View {
        HStack(spacing: 12) {
            CircularMapControl(label: "Profile and settings", action: { model.showingProfile = true; model.haptic.tap() }) {
                Image(systemName: "person.crop.circle").font(.system(size: 23, weight: .medium))
            }
            Button { model.openSearch() } label: {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").fontWeight(.semibold)
                    Text("Search Arc").foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }.padding(.horizontal, 20).frame(height: 58)
            }
            .glassEffect(.regular.interactive(), in: .capsule)
            .glassEffectID("search", in: glass)
            .accessibilityIdentifier("map.search")
            CircularMapControl(label: "Map layers", action: { model.showingLayers = true; model.haptic.tap() }) {
                Image(systemName: "square.3.layers.3d").font(.system(size: 23, weight: .medium))
            }
        }
        .foregroundStyle(.primary)
    }
}
