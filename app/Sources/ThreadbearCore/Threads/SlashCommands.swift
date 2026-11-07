import Foundation

/// A command a message can start with: a skill, a plugin's or the
/// folder's own command, or one of Claude Code's that works from the app
/// (docs/protocol.md, "Slash commands").
public struct SlashCommand: Sendable, Hashable, Codable, Identifiable {
    public var name: String
    public var description: String
    public var argumentHint: String?
    public var id: String { name }

    public init(name: String, description: String = "", argumentHint: String? = nil) {
        self.name = name
        self.description = description
        self.argumentHint = argumentHint
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        argumentHint = try c.decodeIfPresent(String.self, forKey: .argumentHint)
    }
}

public struct SlashCommandsResult: Sendable, Codable {
    public var commands: [SlashCommand]
}

/// The message box's `/` menu: when it shows, what it lists, and what
/// picking a row does to the words.
public enum SlashMenu {
    /// The `/word` at the very start of the message, while the caret is in
    /// it with nothing selected: its range (the `/` included) and the word
    /// so far. Nil once a space follows it or the caret leaves it, so the
    /// menu only shows while the command is being typed.
    public static func token(in text: String, selection: NSRange) -> (range: NSRange, query: String)? {
        let ns = text as NSString
        guard ns.length > 0, ns.character(at: 0) == UInt16(UInt8(ascii: "/")), selection.length == 0 else { return nil }
        var end = 1
        while end < ns.length, let scalar = Unicode.Scalar(ns.character(at: end)), !CharacterSet.whitespacesAndNewlines.contains(scalar) {
            end += 1
        }
        // A picture's chip right after the slash isn't a command.
        let word = ns.substring(with: NSRange(location: 1, length: end - 1))
        guard !word.contains("\u{FFFC}"), selection.location >= 1, selection.location <= end else { return nil }
        return (NSRange(location: 0, length: end), word)
    }

    /// The commands for what's been typed after the `/`, best first: the
    /// name starting with it, then a part of the name (after `:` or `-`)
    /// starting with it, then the name holding it anywhere, then the
    /// description. Alphabetical within each.
    public static func matches(_ commands: [SlashCommand], query: String) -> [SlashCommand] {
        let q = query.lowercased()
        func rank(_ c: SlashCommand) -> Int? {
            let name = c.name.lowercased()
            if q.isEmpty || name.hasPrefix(q) { return 0 }
            let parts = name.split(whereSeparator: { $0 == ":" || $0 == "-" || $0 == "_" })
            if parts.contains(where: { $0.hasPrefix(q) }) { return 1 }
            if name.contains(q) { return 2 }
            if q.count >= 3, c.description.lowercased().contains(q) { return 3 }
            return nil
        }
        var ranked: [(command: SlashCommand, rank: Int)] = []
        for c in commands {
            if let r = rank(c) { ranked.append((c, r)) }
        }
        ranked.sort { a, b in
            if a.rank != b.rank { return a.rank < b.rank }
            return a.command.name.localizedStandardCompare(b.command.name) == .orderedAscending
        }
        return ranked.map(\.command)
    }

    /// Whether Return takes this row without it being moved to: when it
    /// matches by name, and isn't just the whole name already typed (Return
    /// then sends it as it is). A row matching only on its description
    /// would otherwise swap a word Mike typed for an unrelated command.
    public static func picksOnReturn(_ command: SlashCommand, query: String) -> Bool {
        let q = query.lowercased()
        let name = command.name.lowercased()
        if q.isEmpty { return true }
        return name != q && name.contains(q)
    }

    /// What picking `command` puts in place of the token: `/name` and a
    /// space, unless the words after it already start with one.
    public static func replacement(for command: SlashCommand, in text: String, token: NSRange) -> String {
        let ns = text as NSString
        let after = NSMaxRange(token)
        let spaced = after < ns.length && Unicode.Scalar(ns.character(at: after)).map { CharacterSet.whitespacesAndNewlines.contains($0) } == true
        return "/\(command.name)" + (spaced ? "" : " ")
    }

    /// The first line of a description, short enough for one row.
    public static func summary(_ description: String, limit: Int = 140) -> String {
        let line = description.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }
}

public extension RPCClient {
    /// What a message in the thread can start with `/` for. A runner from
    /// before slash commands answers `-32601`.
    func slashCommands(threadId: String) async throws -> [SlashCommand] {
        try await call("threads.commands", .object(["threadId": .string(threadId)]), as: SlashCommandsResult.self, timeout: .seconds(20)).commands
    }

    /// The same for a thread not made yet, in `cwd` on `accountId` (the
    /// runner's default login without one).
    func slashCommands(cwd: String, accountId: String?) async throws -> [SlashCommand] {
        var params: [String: JSONValue] = ["cwd": .string(cwd)]
        if let accountId, !accountId.isEmpty { params["accountId"] = .string(accountId) }
        return try await call("threads.commands", .object(params), as: SlashCommandsResult.self, timeout: .seconds(20)).commands
    }
}
