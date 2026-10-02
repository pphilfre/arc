import ActivityKit
import Foundation

struct ArcActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var instruction: String
        var symbol: String
        var distanceToTurn: String
        var remainingDistance: String
        var arrival: Date
        var currentSpeed: Int
        var averageSpeed: Int
        var units: String
        var sessionDistance: String
        var startedAt: Date
        var arrived: Bool
    }
    var destination: String
    var isNavigation: Bool
}

