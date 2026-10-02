import ActivityKit
import Foundation

@MainActor final class LiveActivityService {
    private var activity: Activity<ArcActivityAttributes>?
    private var lastUpdate = Date.distantPast
    private var lastInstruction = ""
    private var lastState: ArcActivityAttributes.ContentState?
    func start(destination: String, navigation: Bool, state: ArcActivityAttributes.ContentState) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        // Retire orphaned activities after a process restart.
        for old in Activity<ArcActivityAttributes>.activities {
            Task { await old.end(nil, dismissalPolicy: .immediate) }
        }
        activity = try? Activity.request(attributes: .init(destination: destination, isNavigation: navigation),
            content: .init(state: state, staleDate: Date().addingTimeInterval(60)), pushType: nil)
        lastState = state
    }
    func update(_ state: ArcActivityAttributes.ContentState) {
        guard let activity else { return }
        guard Date().timeIntervalSince(lastUpdate) >= 5 || state.instruction != lastInstruction || (state.arrived && !(lastState?.arrived ?? false)) else { return }
        lastUpdate = .now; lastInstruction = state.instruction; lastState = state
        Task { await activity.update(.init(state: state, staleDate: Date().addingTimeInterval(60))) }
    }
    func end() {
        guard let activity else { return }
        self.activity = nil
        let final = lastState.map { ActivityContent(state: $0, staleDate: nil) }
        Task { await activity.end(final, dismissalPolicy: .immediate) }
    }
}
