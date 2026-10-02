import SwiftUI
import SwiftData
import UIKit

struct SearchSheet: View {
    @Bindable var model: ArcModel
    @Query(sort: \RecentSearch.date, order: .reverse) private var recents: [RecentSearch]
    @Query(sort: \SavedPlace.savedAt, order: .reverse) private var saved: [SavedPlace]
    @Environment(\.modelContext) private var context
    @FocusState private var focused: Bool
    @State private var keyboardTop: CGFloat?

    var body: some View {
        GeometryReader { geometry in
        VStack(spacing: 0) {
            Capsule().fill(.secondary.opacity(0.35)).frame(width: 34, height: 5).padding(.top, 10)
                .frame(maxWidth: .infinity).contentShape(Rectangle())
                .gesture(DragGesture().onEnded { if $0.translation.height > 60 { model.dismissSearch() } })
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(prompt, text: $model.query).focused($focused).accessibilityIdentifier("search.query")
                    .submitLabel(.search).autocorrectionDisabled()
                    .onSubmit {
                        focused = false
                        model.recordSearch(model.query)
                        model.search.submit(model.query, proximity: model.location.location?.coordinate)
                    }
                if !model.query.isEmpty {
                    Button { model.clearSearch() } label: { Image(systemName: "xmark.circle.fill") }
                        .foregroundStyle(.secondary).accessibilityLabel("Clear search")
                }
                Button("Done") { focused = false; model.dismissSearch() }.frame(minWidth: 44, minHeight: 44).accessibilityIdentifier("search.done")
            }.frame(minHeight: 52).padding(.horizontal, 18).padding(.vertical, 4)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ScrollView(.horizontal) {
                        HStack(spacing: 10) {
                            ForEach(SearchCategory.all) { category in
                                Button {
                                    focused = false
                                    model.haptic.tap()
                                    model.query = ""
                                    model.search.category(category, proximity: model.location.location?.coordinate)
                                    model.recordSearch(category.name)
                                } label: {
                                    VStack(spacing: 10) {
                                        Image(systemName: category.symbol).font(.title3).frame(width: 52, height: 52)
                                            .glassEffect(.regular.interactive(), in: .circle)
                                        Text(category.name).font(.caption)
                                        .foregroundStyle(model.search.activeCategory?.id == category.id ? model.preferences.accent.color : Color.primary)
                                    }.frame(width: 76)
                                }.buttonStyle(.plain)
                            }
                        }.padding(.horizontal, 20).padding(.vertical, 8)
                    }.scrollIndicators(.hidden)
                    if model.search.busy { ProgressView("Searching nearby…").padding(.horizontal, 24) }
                    if let error = model.search.error {
                        ContentUnavailableView("Search unavailable", systemImage: "wifi.slash", description: Text(error))
                    }
                    if !model.search.rows.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(model.search.rows) { row in
                                Button { focused = false; model.search.select(row) } label: {
                                    PlaceRow(name: row.name, detail: row.detail, symbol: "mappin.circle.fill")
                                }.buttonStyle(.plain)
                                Divider().padding(.leading, 68)
                            }
                        }
                    } else if !model.search.places.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(model.search.places) { place in
                                Button { focused = false; model.select(place) } label: {
                                    PlaceRow(name: place.name, detail: place.address, symbol: "mappin.circle.fill")
                                }.buttonStyle(.plain)
                                Divider().padding(.leading, 68)
                            }
                        }
                    } else if model.query.isEmpty && !model.search.busy {
                        if !saved.isEmpty {
                            Text("Saved places").font(.title3.bold()).padding(.horizontal, 24)
                            ForEach(saved) { item in
                                if let place = item.place {
                                    Button { model.select(place) } label: {
                                        PlaceRow(name: place.name, detail: place.address, symbol: "bookmark.fill")
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                        HStack {
                            Text("Recents").font(.title3.bold())
                            Spacer()
                            if !recents.isEmpty {
                                Button("Clear") { recents.forEach { context.delete($0) }; try? context.save() }.font(.subheadline)
                            }
                        }.padding(.horizontal, 24)
                        if recents.isEmpty {
                            Text("Find a place, an address, or somewhere new.").foregroundStyle(.secondary).padding(.horizontal, 24)
                        }
                        ForEach(recents.prefix(12)) { recent in
                            Button { model.query = recent.query } label: {
                                PlaceRow(name: recent.query, detail: "", symbol: "clock")
                            }.buttonStyle(.plain)
                        }
                    } else if !model.search.busy && model.search.error == nil {
                        ContentUnavailableView.search(text: model.query)
                    }
                }.padding(.bottom, 24)
            }.scrollDismissesKeyboard(.interactively)
            .safeAreaPadding(.bottom, keyboardTop.map { max(0, geometry.frame(in: .global).maxY - $0) } ?? 0)
        }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
            guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            withAnimation(.easeOut(duration: 0.25)) { keyboardTop = frame.minY }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.25)) { keyboardTop = nil }
        }
        .task(id: model.query) {
            if model.query.isEmpty {
                guard model.search.activeCategory == nil else { return }
                model.search.search("", proximity: model.location.location?.coordinate)
                return
            }
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            guard !Task.isCancelled else { return }
            guard model.search.submittedQuery != model.query else { return }
            model.search.search(model.query, proximity: model.location.location?.coordinate)
        }
    }
    private var prompt: String {
        switch model.searchPurpose { case .origin: "Choose a start"; case .stop: "Add a stop"; case .destination: "Search Arc" }
    }
}

struct PlaceRow: View {
    let name: String
    let detail: String
    let symbol: String
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.title3).foregroundStyle(.tint).frame(width: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(name).font(.body.weight(.medium)).foregroundStyle(.primary)
                if !detail.isEmpty { Text(detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(2) }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
        }.padding(.horizontal, 24).padding(.vertical, 14).contentShape(Rectangle())
    }
}
