import SwiftUI
import SwiftData
import MapboxMaps

@main struct ArcApp: App {
    @State private var model: ArcModel
    private let container: ModelContainer?
    private let storageFailure: String?

    init() {
        MapboxOptions.accessToken = (Bundle.main.object(forInfoDictionaryKey: "MBXAccessToken") as? String) ?? ""
        _model = State(initialValue: ArcModel())
        do {
            container = try ModelContainer(for: SavedPlace.self, RecentSearch.self, Journey.self,
                configurations: ModelConfiguration(cloudKitDatabase: .none))
            storageFailure = nil
        } catch {
            container = nil
            storageFailure = "Arc couldn't open its local storage. Restart the app to try again."
        }
    }
    var body: some Scene {
        WindowGroup {
            if let container {
                ArcView(model: model)
                    .modelContainer(container)
                    .tint(model.preferences.accent.color)
                    .preferredColorScheme(model.preferences.appearance.colorScheme)
            } else {
                ContentUnavailableView("Local storage unavailable", systemImage: "externaldrive.badge.exclamationmark",
                    description: Text(storageFailure ?? "Restart Arc to try again."))
            }
        }
    }
}
