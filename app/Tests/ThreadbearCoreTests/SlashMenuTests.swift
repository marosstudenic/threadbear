import Foundation
import XCTest
@testable import ThreadbearCore

/// docs/protocol.md, "Slash commands".
final class SlashMenuTests: XCTestCase {
    private func caret(_ at: Int) -> NSRange { NSRange(location: at, length: 0) }

    func testTheMenuShowsOnlyWhileTheFirstWordIsASlashBeingTyped() {
        XCTAssertEqual(SlashMenu.token(in: "/", selection: caret(1))?.query, "")
        XCTAssertEqual(SlashMenu.token(in: "/gri", selection: caret(4))?.query, "gri")
        XCTAssertEqual(SlashMenu.token(in: "/gri", selection: caret(4))?.range, NSRange(location: 0, length: 4))
        // Caret back inside the word, with words after it: still the word.
        let mid = SlashMenu.token(in: "/gri my plan", selection: caret(2))
        XCTAssertEqual(mid?.query, "gri")
        XCTAssertEqual(mid?.range, NSRange(location: 0, length: 4))
        // Past the space, before the slash, a selection, or no slash first.
        XCTAssertNil(SlashMenu.token(in: "/grilling ", selection: caret(10)))
        XCTAssertNil(SlashMenu.token(in: "/gri", selection: caret(0)))
        XCTAssertNil(SlashMenu.token(in: "/gri", selection: NSRange(location: 1, length: 2)))
        XCTAssertNil(SlashMenu.token(in: "hi /gri", selection: caret(7)))
        XCTAssertNil(SlashMenu.token(in: " /gri", selection: caret(5)))
        XCTAssertNil(SlashMenu.token(in: "", selection: caret(0)))
        XCTAssertNil(SlashMenu.token(in: "/\u{FFFC}", selection: caret(2)), "a picture's chip")
        XCTAssertNil(SlashMenu.token(in: "/a\nb", selection: caret(4)))
    }

    func testMatchesRankPrefixThenPartThenAnywhereThenDescription() {
        let commands = [
            SlashCommand(name: "to-issues", description: "Break a plan into issues"),
            SlashCommand(name: "review", description: "Review the changes"),
            SlashCommand(name: "egm:egm-review", description: "Goldfish review"),
            SlashCommand(name: "code-review", description: "Find bugs"),
            SlashCommand(name: "grilling", description: "Stress-test a plan"),
            SlashCommand(name: "preview", description: "x"),
        ]
        XCTAssertEqual(SlashMenu.matches(commands, query: "").map(\.name), ["code-review", "egm:egm-review", "grilling", "preview", "review", "to-issues"])
        XCTAssertEqual(SlashMenu.matches(commands, query: "rev").map(\.name), ["review", "code-review", "egm:egm-review", "preview"])
        XCTAssertEqual(SlashMenu.matches(commands, query: "REV").map(\.name), ["review", "code-review", "egm:egm-review", "preview"])
        XCTAssertEqual(SlashMenu.matches(commands, query: "issues").map(\.name), ["to-issues"])
        XCTAssertEqual(SlashMenu.matches(commands, query: "plan").map(\.name), ["grilling", "to-issues"], "by description, once it's three letters")
        XCTAssertEqual(SlashMenu.matches(commands, query: "pl").map(\.name), [])
        XCTAssertEqual(SlashMenu.matches(commands, query: "zzz").map(\.name), [])
    }

    func testPickingPutsTheNameAndOneSpace() {
        let grill = SlashCommand(name: "grilling")
        XCTAssertEqual(SlashMenu.replacement(for: grill, in: "/gr", token: NSRange(location: 0, length: 3)), "/grilling ")
        XCTAssertEqual(SlashMenu.replacement(for: grill, in: "/gr my plan", token: NSRange(location: 0, length: 3)), "/grilling")
    }

    func testReturnTakesANameMatchButNotAWholeNameOrADescriptionMatch() {
        let api = SlashCommand(name: "claude-api", description: "Pick a model and call it")
        XCTAssertTrue(SlashMenu.picksOnReturn(api, query: ""))
        XCTAssertTrue(SlashMenu.picksOnReturn(api, query: "cla"))
        XCTAssertTrue(SlashMenu.picksOnReturn(api, query: "API"))
        XCTAssertFalse(SlashMenu.picksOnReturn(api, query: "model"), "only its description matches")
        XCTAssertFalse(SlashMenu.picksOnReturn(api, query: "claude-api"), "typed in full: Return sends it")
    }

    func testSummaryIsTheFirstLineCutShort() {
        XCTAssertEqual(SlashMenu.summary("  One line.  \nMore."), "One line.")
        XCTAssertEqual(SlashMenu.summary(String(repeating: "a", count: 200), limit: 10), "aaaaaaaaa…")
        XCTAssertEqual(SlashMenu.summary(""), "")
    }

    func testDecodesWithoutADescription() throws {
        let json = #"{"commands":[{"name":"grilling","description":"Grill"},{"name":"x","argumentHint":"<f>"}]}"#
        let result = try JSONDecoder().decode(SlashCommandsResult.self, from: Data(json.utf8))
        XCTAssertEqual(result.commands, [SlashCommand(name: "grilling", description: "Grill"), SlashCommand(name: "x", argumentHint: "<f>")])
    }
}
