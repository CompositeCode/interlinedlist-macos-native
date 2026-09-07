// TrendingTagsStrip
//
// The timeline's horizontal trending-tags strip (work-consolidation.md G20).
// Tapping a tag applies the timeline's existing tag filter; tapping the active
// one clears it.
//
// SwiftUI-only (no AppKit). Consumes only `InterlinedDomain` per Decision 0003.

import SwiftUI
import InterlinedDomain

struct TrendingTagsStrip: View {

    @Environment(\.appEnvironment) private var environment
    /// The currently applied filter, so the active chip reads as selected.
    let activeTag: String?
    /// Applies (or clears) the filter. Owned by the timeline.
    let onSelect: (String?) async -> Void

    @State private var viewModel: TrendingTagsViewModel?

    var body: some View {
        Group {
            if let viewModel, viewModel.isVisible {
                strip(viewModel)
            }
        }
        .task {
            if viewModel == nil {
                let model = TrendingTagsViewModel(service: environment?.tags)
                viewModel = model
                await model.load()
            }
        }
    }

    @ViewBuilder
    private func strip(_ viewModel: TrendingTagsViewModel) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(viewModel.tags) { tag in
                    let isActive = tag.name.caseInsensitiveCompare(activeTag ?? "") == .orderedSame
                    Button {
                        // Tapping the active chip clears the filter.
                        Task { await onSelect(isActive ? nil : tag.name) }
                    } label: {
                        HStack(spacing: 4) {
                            Text("#\(tag.name)")
                            if tag.count > 0 {
                                Text("\(tag.count)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.ilMono(10))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.tint.opacity(0.12)),
                            in: Capsule()
                        )
                        .foregroundStyle(isActive ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        isActive
                            ? "Clear filter for tag \(tag.name)"
                            : "Filter timeline by tag \(tag.name), \(tag.count) posts"
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }
}
