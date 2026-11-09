import SwiftUI

struct CauseBadge: View {
    let symbol: String
    let tint: CauseColor
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(tint.swiftUIColor.gradient, in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
            .accessibilityHidden(true)
    }
}

extension View {
    /// Rounded card on a grouped background.
    func cardStyle() -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// Horizontal row of pill buttons for switching between causes.
struct CauseChipBar: View {
    let causes: [Cause]
    @Binding var selection: UUID?
    /// Adds a leading "All" chip that sets the selection to nil.
    var allowsAll = false
    var onAdd: (() -> Void)?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if allowsAll {
                        chip(title: "All", symbol: "square.grid.2x2.fill", tint: .gray, selected: selection == nil) {
                            selection = nil
                        }
                    }
                    ForEach(causes) { cause in
                        chip(title: cause.name, symbol: cause.symbol, tint: cause.tint, selected: selection == cause.uuid) {
                            selection = cause.uuid
                        }
                        .id(cause.uuid)
                    }
                    if let onAdd {
                        Button(action: onAdd) {
                            Image(systemName: "plus")
                                .font(.subheadline.weight(.semibold))
                                .frame(width: 38, height: 38)
                                .background(Color(.secondarySystemGroupedBackground), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add a cause")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
            }
            .onAppear { scroll(proxy) }
            .onChange(of: selection) { scroll(proxy) }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func scroll(_ proxy: ScrollViewProxy) {
        guard let selection else { return }
        withAnimation { proxy.scrollTo(selection, anchor: .center) }
    }

    private func chip(title: String, symbol: String, tint: CauseColor, selected: Bool,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.caption.weight(.bold))
                Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
            }
            .padding(.horizontal, 14)
            .frame(height: 38)
            .foregroundStyle(selected ? tint.foreground : Color.primary)
            .background {
                if selected {
                    Capsule().fill(tint.swiftUIColor.gradient)
                } else {
                    Capsule().fill(Color(.secondarySystemGroupedBackground))
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct StatusBadge: View {
    let status: VerificationStatus

    var body: some View {
        Label(status.label, systemImage: status.symbol)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(status.color)
            .labelStyle(.titleAndIcon)
    }
}

struct EntryRow: View {
    let entry: TimeEntry
    var showCause = true

    var body: some View {
        HStack(spacing: 12) {
            CauseBadge(symbol: entry.cause?.symbol ?? "questionmark",
                       tint: entry.cause?.tint ?? .gray, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(showCause ? (entry.cause?.name ?? "Unknown cause") : Fmt.date(entry.startDate))
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Fmt.hm(entry.duration)).font(.headline).monospacedDigit()
                if entry.status != .notRequired { StatusBadge(status: entry.status) }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        let date = showCause ? Fmt.date(entry.startDate) : ""
        if entry.notes.isEmpty { return date }
        return date.isEmpty ? entry.notes : "\(date) · \(entry.notes)"
    }
}

struct StatTile: View {
    let title: String
    let value: String
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold)).monospacedDigit().foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
