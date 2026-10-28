import AppKit
import SwiftUI

/// Janela do desinstalador: mostra o app e tudo o que foi achado, e só move o que estiver marcado.
struct UninstallerView: View {
    let model: Uninstaller
    let onClose: () -> Void
    /// Desligado no modo `--snapshot` (o ImageRenderer não desenha ScrollView).
    var scrolls = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch model.phase {
            case .refused(let refusal):
                refused(refusal)
            case .scanning:
                header
                progress(L(.scanning))
            case .review:
                header
                review
            case .removing:
                header
                progress(L(.movingToTrash))
            case .done:
                done
            }
        }
        .frame(minWidth: 520, minHeight: 440)
    }

    // MARK: Partes

    @ViewBuilder private var header: some View {
        if let app = model.app {
            HStack(spacing: 14) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                    .resizable()
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text(app.name)
                        .font(.title2.weight(.semibold))
                    Text([app.version, app.bundleID].compactMap { $0 }.joined(separator: " · "))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text(abbreviated(app.url.deletingLastPathComponent()))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }
            .padding(20)
        }
    }

    private func progress(_ text: String) -> some View {
        VStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(text).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var review: some View {
        if model.isRunning {
            Banner(symbol: "exclamationmark.triangle.fill", color: .orange, text: L(.appIsRunning)) {
                Button(L(.quitApp), action: model.quitApp)
            }
        }
        if let copy = model.otherCopies.first {
            Banner(symbol: "info.circle.fill", color: .blue,
                   text: L(.otherCopies, abbreviated(copy.deletingLastPathComponent()))) { EmptyView() }
        }
        Divider()
        let list = VStack(alignment: .leading, spacing: 14) {
            ForEach(LeftoverKind.allCases, id: \.self) { kind in
                let rows = model.items.filter { $0.kind == kind }
                if !rows.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(kind.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(rows) { LeftoverRow(model: model, item: $0) }
                    }
                }
            }
            if model.items.count == 1 {
                Text(L(.noLeftovers))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        if scrolls {
            ScrollView { list }
        } else {
            list
            Spacer(minLength: 0)
        }
        Divider()
        let chosen = model.selectedItems
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L(.selectedSummary, chosen.count, formatBytes(chosen.reduce(0) { $0 + $1.size })))
                    .font(.callout.weight(.medium))
                Text(L(.trashNote))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(L(.cancel), action: onClose)
                .keyboardShortcut(.cancelAction)
            Button(L(.moveToTrash), action: model.remove)
                .keyboardShortcut(.defaultAction)
                .disabled(chosen.isEmpty || model.isRunning)
        }
        .padding(16)
    }

    private var done: some View {
        let ok = model.failed.isEmpty
        return VStack(spacing: 12) {
            Spacer(minLength: 0)
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(ok ? .green : .orange)
            Text(ok ? L(.doneTitle) : L(.partialTitle))
                .font(.title2.weight(.semibold))
            if !model.removed.isEmpty {
                Text(L(.doneDetail, model.removed.count, formatBytes(model.removed.reduce(0) { $0 + $1.size })))
                    .foregroundStyle(.secondary)
            }
            if model.needsRestart {
                Text(L(.restartNote))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if !ok {
                Text(L(.protectedHelp))
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(model.failed.prefix(6)) { item in
                        Text(abbreviated(item.url))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if model.failed.count > 6 {
                        Text("+\(model.failed.count - 6)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: 440)
            }
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                Button(L(.showTrash)) {
                    NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash"))
                }
                Spacer()
                if ok {
                    Button(L(.closeButton), action: onClose)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button(L(.closeButton), action: onClose)
                        .keyboardShortcut(.cancelAction)
                    Button(L(.askFinder), action: model.moveFailedWithFinder)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(16)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func refused(_ refusal: UninstallRefusal) -> some View {
        VStack(spacing: 12) {
            Spacer(minLength: 0)
            if let url = model.chosenURL {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 56, height: 56)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "hand.raised.circle.fill")
                            .font(.system(size: 22))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .orange)
                    }
                Text(url.deletingPathExtension().lastPathComponent)
                    .font(.title2.weight(.semibold))
            }
            Text(refusal.message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 400)
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button(L(.closeButton), action: onClose)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private func abbreviated(_ url: URL) -> String {
    (url.path as NSString).abbreviatingWithTildeInPath
}

struct LeftoverRow: View {
    let model: Uninstaller
    let item: Leftover

    var body: some View {
        let on = model.selected.contains(item.id)
        HStack(spacing: 10) {
            // Caixa desenhada em SwiftUI (a do AppKit não aparece no modo --snapshot).
            Button {
                if on { model.selected.remove(item.id) } else { model.selected.insert(item.id) }
            } label: {
                Image(systemName: on ? "checkmark.square.fill" : "square")
                    .font(.system(size: 15))
                    .foregroundStyle(on ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.url.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(abbreviated(item.url.deletingLastPathComponent()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            if item.needsAdmin {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help(L(.needsPassword))
            }
            Text(formatBytes(item.size))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help(L(.showInFinder))
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .opacity(on ? 1 : 0.6)
    }
}

private struct Banner<Accessory: View>: View {
    let symbol: String
    let color: Color
    let text: String
    @ViewBuilder let accessory: () -> Accessory

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            accessory()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(color.opacity(0.12)))
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }
}
