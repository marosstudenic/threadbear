import AppKit
import SwiftUI
import ThreadbearCore

/// The message box's `/` menu (docs/protocol.md, "Slash commands"): the
/// commands a message can start with, listed while a `/word` at the very
/// start is being typed. The text view feeds it the words and caret
/// (`update`) and hands it Up, Down, Return, Tab and Esc first (`key`);
/// picking a row puts `/name ` in place of the word.
@MainActor
@Observable
final class SlashMenuModel {
    /// The list for the box's thread or new thread, as the runner last said.
    private(set) var commands: [SlashCommand] = []
    /// The rows on show, best match first.
    private(set) var rows: [SlashCommand] = []
    var selected = 0
    /// The `/word` being typed, while there is one.
    private(set) var token: NSRange?
    /// The words when Esc closed it (or a row was picked), so it stays shut
    /// until they change.
    private var shutFor: String?
    private var text = ""
    private var lastQuery: String?
    @ObservationIgnored private var loading: Task<Void, Never>?
    @ObservationIgnored private var loadedAt: Date?
    @ObservationIgnored private var loadedFor: String?
    /// Asks the runner; set by the composer, for its thread or new thread.
    @ObservationIgnored var fetch: (() async -> [SlashCommand])?
    /// Which list `fetch` gets: a different one starts afresh.
    @ObservationIgnored var key = ""

    var isShown: Bool { token != nil && !rows.isEmpty && shutFor != text }

    func update(text: String, selection: NSRange, focused: Bool) {
        self.text = text
        let found = focused ? SlashMenu.token(in: text, selection: selection) : nil
        if found == nil { shutFor = nil }
        let was = token.map { (text as NSString).length >= NSMaxRange($0) ? (text as NSString).substring(with: $0) : "" }
        token = found?.range
        guard let found else {
            rows = []
            lastQuery = nil
            return
        }
        // A fresh `/` asks again if the list is old or for another thread.
        if was == nil { load() }
        filter(found.query)
    }

    /// Typing narrows it from the best match; a list coming in, or the
    /// caret moving, keeps the row picked where it can.
    private func filter(_ query: String) {
        let keep = query == lastQuery && rows.indices.contains(selected) ? rows[selected].name : nil
        lastQuery = query
        rows = SlashMenu.matches(commands, query: query)
        selected = keep.flatMap { name in rows.firstIndex { $0.name == name } } ?? 0
    }

    private func load() {
        guard let fetch else { return }
        if loadedFor == key, let loadedAt, Date().timeIntervalSince(loadedAt) < 30 { return }
        if loadedFor != key { commands = [] }
        loading?.cancel()
        let key = key
        loading = Task { [weak self] in
            let list = await fetch()
            guard let self, !Task.isCancelled, self.key == key else { return }
            self.commands = list
            self.loadedAt = Date()
            self.loadedFor = key
            if let token = self.token, (self.text as NSString).length >= NSMaxRange(token) {
                let word = (self.text as NSString).substring(with: NSRange(location: 1, length: token.length - 1))
                self.filter(word)
            }
        }
    }

    func move(_ by: Int) {
        guard !rows.isEmpty else { return }
        selected = (selected + by + rows.count) % rows.count
    }

    func shut() { shutFor = text }

    /// Puts the picked command in place of the `/word` (one undo step).
    func pick(_ command: SlashCommand, in textView: NSTextView) {
        guard let token, (textView.string as NSString).length >= NSMaxRange(token) else { return }
        let replacement = SlashMenu.replacement(for: command, in: textView.string, token: token)
        textView.insertText(replacement, replacementRange: token)
        shutFor = textView.string
        textView.window?.makeFirstResponder(textView)
    }

    /// A key while it's shown: true if the menu took it.
    func key(_ event: NSEvent, in textView: NSTextView) -> Bool {
        guard isShown, !textView.hasMarkedText() else { return false }
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        switch event.keyCode {
        case 126 where mods.isEmpty: move(-1)
        case 125 where mods.isEmpty: move(1)
        case 36, 76, 48:
            guard mods.isEmpty, rows.indices.contains(selected) else { return false }
            pick(rows[selected], in: textView)
        case 53: shut()
        default: return false
        }
        return true
    }
}

/// The menu itself: a card floating over the transcript, just above the
/// box, one row a command with its name, what it takes, and what it does.
struct SlashCommandMenu: View {
    let model: SlashMenuModel
    let pick: (SlashCommand) -> Void
    @Environment(\.colorScheme) private var colorScheme

    private static var rowHeight: CGFloat { zoomed(44) }

    /// Seven rows at most, then it scrolls.
    static func height(rows: Int) -> CGFloat { CGFloat(min(rows, 7)) * rowHeight + zoomed(10) }

    var body: some View {
        ScrollViewReader { scroller in
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    ForEach(Array(model.rows.enumerated()), id: \.element.name) { index, command in
                        SlashCommandRow(command: command, selected: index == model.selected) { pick(command) }
                            .id(command.name)
                    }
                }
                .padding(zoomed(5))
            }
            .scrollIndicators(.automatic)
            .frame(height: Self.height(rows: model.rows.count))
            .onChange(of: model.selected) { _, index in
                guard model.rows.indices.contains(index) else { return }
                scroller.scrollTo(model.rows[index].name)
            }
        }
        .background {
            RoundedRectangle(cornerRadius: zoomed(12), style: .continuous)
                .fill(Color(nsColor: colorScheme == .dark ? .controlBackgroundColor : .textBackgroundColor))
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.14), radius: zoomed(10), y: zoomed(3))
        }
        .overlay {
            RoundedRectangle(cornerRadius: zoomed(12), style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
        }
    }
}

private struct SlashCommandRow: View {
    let command: SlashCommand
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: zoomed(1)) {
                HStack(spacing: zoomed(6)) {
                    Text("/" + command.name)
                        .font(.system(size: TypeScale.chip, weight: .semibold))
                        .lineLimit(1)
                    if let hint = command.argumentHint, !hint.isEmpty {
                        Text(hint)
                            .font(.system(size: TypeScale.chip - 1))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                let summary = SlashMenu.summary(command.description)
                if !summary.isEmpty {
                    Text(summary)
                        .font(.system(size: TypeScale.chip - 1))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .padding(.horizontal, zoomed(9))
            .frame(maxWidth: .infinity, minHeight: zoomed(44), maxHeight: zoomed(44), alignment: .leading)
            .background(RoundedRectangle(cornerRadius: zoomed(7)).fill(fill))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .tip(command.description.isEmpty ? "Start the message with /\(command.name)" : SlashMenu.summary(command.description, limit: 400))
    }

    private var fill: Color {
        if selected { return Color.accentColor.opacity(0.18) }
        return Color.primary.opacity(hovering ? 0.06 : 0)
    }
}

extension AppModel {
    /// What a message in the thread (or the next new thread) can start with
    /// `/` for. Empty when the runner can't say: an older one, Codex, a new
    /// thread on another runner, or no connection.
    func slashCommands(threadId: String?) async -> [SlashCommand] {
        do {
            if let threadId {
                guard let client = client(for: threadId) else { return [] }
                return try await client.slashCommands(threadId: threadId)
            }
            let cwd = newThreadCwd ?? draftLogins.defaults.cwd
            guard newThreadRunnerId == nil, let client, !cwd.isEmpty else { return [] }
            return try await client.slashCommands(cwd: cwd, accountId: newThreadAccountId)
        } catch {
            AppLog.write("slash", "no commands: \(error)")
            return []
        }
    }
}
