import Foundation

enum AnnotationRole: String { case saved, dropped, search, category, selected, destination, drivingPOI }
struct ArcAnnotation: Identifiable, Equatable {
    let place: Place
    let role: AnnotationRole
    var id: String { place.id }
    /// Later roles take precedence without deleting a retained saved/dropped place.
    static func merge(_ groups: [[ArcAnnotation]]) -> [ArcAnnotation] {
        var lookup: [String: ArcAnnotation] = [:]
        for annotation in groups.flatMap({ $0 }) { lookup[annotation.id] = annotation }
        return lookup.values.sorted { $0.id < $1.id }
    }
}
