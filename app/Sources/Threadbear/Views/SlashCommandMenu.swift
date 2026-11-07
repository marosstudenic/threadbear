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
    /// The rows on show, best match first.
    private(set) var rows: [SlashCommand] = []
    private(set) var selected = 0
    /// Whether a `/word` is being typed in the focused box.
    private(set) var typing = false
    /// Esc closed it (or a row was picked) for these words, so it stays
    /// shut until they change.
    private var shutFor: String?
    @ObservationIgnored private var text = ""
    @ObservationIgnored private var query = ""
    /// Moved with Up or Down since the rows last changed: Return then takes
    /// the row even if it only matched on its description.
    @ObservationIgnored private var moved = false
    /// Each thread's (or new thread's) list, as the runner last said.
    @ObservationIgnored private var lists: [String: (at: Date, commands: [SlashCommand])] = [:]
    @ObservationIgnored private var fetching: Set<String> = []
    @ObservationIgnored private var fetch: (() async -> [SlashCommand]?)?
    @ObservationIgnored private(set) var key = ""

    var isShown: Bool { typing && !rows.isEmpty && shutFor != text }

    /// Which list it shows, and how to get it. Set as the box is drawn, before
    /// its words are, so another thread's list never shows for a moment.
    func configure(key: String, fetch: @escaping () async -> [SlashCommand]?) {
        self.fetch = fetch
        guard key != self.key else { return }
        self.key = key
        // Not while SwiftUI is drawing: rows are observed.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.key == key else { return }
            self.refilter()
            if self.typing { self.load() }
        }
    }

    func update(text: String, selection: NSRange, focused: Bool) {
        self.text = text
        let found = focused ? SlashMenu.token(in: text, selection: selection) : nil
        if found == nil, shutFor != nil { shutFor = nil }
        let started = found != nil && !typing
        if typing != (found != nil) { typing = found != nil }
        guard let found else {
            if !rows.isEmpty { rows = [] }
            return
        }
        if started || found.query != query {
            query = found.query
            refilter()
        }
        // A fresh `/` asks again if the list is old.
        if started { load() }
    }

    private func refilter() {
        let fresh = typing ? SlashMenu.matches(lists[key]?.commands ?? [], query: query) : []
        let keep = rows.indices.contains(selected) ? rows[selected].name : nil
        if fresh != rows {
            rows = fresh
            moved = false
            let index = keep.flatMap { name in fresh.firstIndex { $0.name == name } } ?? 0
            selected = query.isEmpty ? index : 0
        } else if !rows.indices.contains(selected) {
            selected = 0
        }
    }

    private func load() {
        guard let fetch, !fetching.contains(key) else { return }
        if let cached = lists[key], Date().timeIntervalSince(cached.at) < 30 { return }
        let key = key
        fetching.insert(key)
        Task { [weak self] in
            let list = await fetch()
            guard let self else { return }
            self.fetching.remove(key)
            // A failed ask (no connection yet) isn't kept: the next `/` asks again.
            guard let list else { return }
            self.lists[key] = (Date(), list)
            if self.key == key { self.refilter() }
        }
    }

    func move(_ by: Int) {
        guard !rows.isEmpty else { return }
        selected = (selected + by + rows.count) % rows.count
        moved = true
    }

    func shut() { shutFor = text }

    /// Puts the picked command in place of the `/word` (one undo step).
    /// False when the box no longer starts with one.
    @discardableResult
    func pick(_ command: SlashCommand, in textView: NSTextView) -> Bool {
        guard let token = SlashMenu.token(in: textView.string, selection: textView.selectedRange()) else { return false }
        let replacement = SlashMenu.replacement(for: command, in: textView.string, token: token.range)
        textView.window?.makeFirstResponder(textView)
        textView.insertText(replacement, replacementRange: token.range)
        shutFor = textView.string
        return true
    }

    /// A key while it's shown: true if the menu took it. Return takes a row
    /// that matches by name, or one moved to; otherwise (a whole name typed,
    /// or only a description matching) it sends as before.
    func key(_ event: NSEvent, in textView: NSTextView) -> Bool {
        guard isShown, !textView.hasMarkedText(), rows.indices.contains(selected) else { return false }
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let row = rows[selected]
        switch event.keyCode {
        case 126 where mods.isEmpty: move(-1)
        case 125 where mods.isEmpty: move(1)
        case 48 where mods.isEmpty:
            return pick(row, in: textView)
        case 36 where mods.isEmpty, 76 where mods.isEmpty:
            guard moved || SlashMenu.picksOnReturn(row, query: query) else { return false }
            return pick(row, in: textView)
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
    /// `/` for. Empty when there's none to have: an older runner, Codex, a
    /// new thread on another runner.
    /// Nil when it couldn't ask (no connection yet), so the menu asks again.
    func slashCommands(threadId: String?) async -> [SlashCommand]? {
        do {
            if let threadId {
                guard let client = client(for: threadId) else { return nil }
                return try await client.slashCommands(threadId: threadId)
            }
            guard newThreadRunnerId == nil else { return [] }
            let cwd = newThreadCwd ?? draftLogins.defaults.cwd
            guard let client, !cwd.isEmpty else { return nil }
            return try await client.slashCommands(cwd: cwd, accountId: newThreadAccountId)
        } catch let RPCError.server(code, _) where code == RPCError.methodNotFound {
            return []
        } catch {
            AppLog.write("slash", "no commands: \(error)")
            return nil
        }
    }
}
