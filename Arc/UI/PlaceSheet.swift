import SwiftUI
import SwiftData

struct PlaceSheet: View {
    @Bindable var model: ArcModel
    let place: Place
    @Query private var saved: [SavedPlace]
    @Environment(\.openURL) private var openURL
    private var isSaved: Bool { saved.contains { $0.placeID == place.id } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(place.name).font(.system(.title, design: .rounded, weight: .bold))
                        Text(place.category.capitalized).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { model.dismissPlace() } label: { Image(systemName: "xmark").frame(width: 36, height: 36) }
                        .buttonStyle(.glass).accessibilityLabel("Close place")
                }
                if !place.address.isEmpty { Text(place.address).font(.subheadline).foregroundStyle(.secondary) }
                if let fix = model.location.location {
                    Label(model.preferences.units.distance(fix.distance(from: place.location)), systemImage: "location")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    Button { model.directions(to: place) } label: { Label("Directions", systemImage: "arrow.turn.up.right").frame(maxWidth: .infinity) }
                        .buttonStyle(.glassProminent).controlSize(.large)
                    Button { model.toggleSave(place) } label: { Image(systemName: isSaved ? "bookmark.fill" : "bookmark") }
                        .buttonStyle(.glass).controlSize(.large).accessibilityLabel(isSaved ? "Unsave place" : "Save place")
                    ShareLink(item: place.shareText) { Image(systemName: "square.and.arrow.up") }
                        .buttonStyle(.glass).controlSize(.large)
                }
                if let imageURL = place.imageURL {
                    AsyncImage(url: imageURL) { image in image.resizable().scaledToFill() } placeholder: { Color.secondary.opacity(0.08) }
                        .frame(height: 180).clipShape(.rect(cornerRadius: 20))
                }
                OpeningHoursView(schedule: place.openingSchedule)
                if let website = place.website { Link(destination: website) { Label("Website", systemImage: "globe") } }
                if let phone = place.phone {
                    Button {
                        let digits = phone.filter { $0.isNumber || $0 == "+" }
                        if let url = URL(string: "tel:\(digits)") { openURL(url) }
                    } label: { Label(phone, systemImage: "phone") }
                }
                Divider()
                Button {
                    model.origin = place; model.selectedPlace = nil; model.openSearch(.destination)
                } label: { Label("Use as starting point", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }
                if model.planning {
                    Button {
                        model.stops.append(place); model.selectedPlace = nil
                        Task { await model.calculate() }
                    } label: { Label("Add stop", systemImage: "plus.circle") }
                }
                RichPlaceInformationPlaceholder()
            }.padding(24).padding(.top, 8)
        }
    }
}

/// Deliberate seam for a future provider; never presents fabricated ratings or reviews.
struct RichPlaceInformationPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("More about this place").font(.headline)
            Text("Reviews and richer place details will appear here in a future version.")
                .font(.footnote).foregroundStyle(.secondary)
        }.padding(.vertical, 12)
    }
}

