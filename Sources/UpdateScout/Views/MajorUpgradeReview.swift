import SwiftUI

/// Shown before any major-version jump is queued: from Update All, a section's
/// Update all, or a single card. Each major upgrade is opt-in, its notes can be
/// read in place, and nothing proceeds until the user confirms they've
/// reviewed them — a new major version of a paid app is often a new purchase.
struct MajorUpgradeReview: View {
    @EnvironmentObject var controller: UpdateController
    let request: UpdateController.ReviewRequest
    @Environment(\.dismiss) private var dismiss

    @State private var included: Set<String> = []
    @State private var expanded: Set<String> = []
    @State private var confirmed = false

    /// Clicking Update on one card already says "this one", so it starts
    /// included. From Update All, every major starts excluded.
    private var isSingle: Bool { request.majors.count == 1 && request.others.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(request.majors) { item in row(item) }
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: 380)
            .fixedSize(horizontal: false, vertical: true)

            Toggle(isOn: $confirmed) {
                Text("I've reviewed these and understand a major upgrade may need a new licence.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .toggleStyle(.checkbox)

            footer
        }
        .padding(20)
        .frame(width: 520)
        .background(GlassBackground())
        .onAppear { if isSingle { included = Set(request.majors.map(\.id)) } }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 40, height: 40)
                .background(Color.orange.opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(isSingle ? "Review major upgrade" : "Review major upgrades")
                    .font(.title2.weight(.semibold))
                Text(request.others.isEmpty
                     ? "Check what's changed before installing."
                     : "^[\(request.others.count) other update](inflect: true) will install as usual. Choose which major upgrades to include.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func row(_ item: UpdateItem) -> some View {
        let style = SourceStyle.forSource(item.sourceID)
        let isOpen = expanded.contains(item.id)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                AppIconView(appPath: item.appPath, style: style, size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name).font(.callout.weight(.semibold))
                    HStack(spacing: 4) {
                        Text(item.installedVersion).foregroundStyle(.secondary)
                        Image(systemName: "arrow.right").font(.system(size: 8)).foregroundStyle(.tertiary)
                        Text(item.latestVersion).foregroundStyle(style.color).fontWeight(.medium)
                    }
                    .font(.caption.monospacedDigit())
                }
                Spacer()
                Button {
                    withAnimation(.smooth(duration: 0.25)) {
                        if isOpen { expanded.remove(item.id) } else { expanded.insert(item.id) }
                    }
                } label: {
                    Label("Notes", systemImage: "chevron.right")
                        .labelStyle(.titleAndIcon)
                        .font(.caption)
                }
                .glass().controlSize(.small)
                Toggle("Include", isOn: Binding(
                    get: { included.contains(item.id) },
                    set: { on in if on { included.insert(item.id) } else { included.remove(item.id) } }))
                    .toggleStyle(.switch).controlSize(.small)
            }
            if isOpen { notes(for: item) }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.06)))
    }

    @ViewBuilder
    private func notes(for item: UpdateItem) -> some View {
        if let text = item.releaseNotes, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ScrollView {
                Text(UpdateDetailView.attributed(from: text))
                    .font(.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 160)
        } else if let url = (item.releaseNotesURL ?? item.url).flatMap(URL.init(string:)) {
            Link(destination: url) {
                Label("No notes here — open the vendor's page", systemImage: "safari")
            }
            .font(.callout)
        } else {
            Text("This update doesn't publish release notes.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button("Cancel") {
                controller.review = nil
                dismiss()
            }
            .glass()
            .keyboardShortcut(.cancelAction)
            Spacer()
            if !request.others.isEmpty {
                Button("Skip these, update the rest") {
                    controller.finishReview(including: [])
                    dismiss()
                }
                .glass()
            }
            Button {
                controller.finishReview(including: request.majors.filter { included.contains($0.id) })
                dismiss()
            } label: {
                Label("Proceed", systemImage: "arrow.down.to.line")
            }
            .glassProminent(.orange)
            .keyboardShortcut(.defaultAction)
            .disabled(!confirmed || (included.isEmpty && request.others.isEmpty))
        }
    }
}
