import AppKit
import SwiftUI
import Testing
@testable import BearDock

// A group narrower than its tabs keeps to its own slot: the tabs shorten
// and its panel's content starts at the group's left edge. Tabs that kept
// their full widths made the bar, and so the group, wider than its slot,
// and the content was centred in that, run under whatever was to the right
// (a list panel's rows under Threadbear's panel rail, 7 Nov).

@MainActor
private final class Frames {
    var content: [PanelID: CGRect] = [:]
}

@MainActor @Test func aNarrowGroupsTabsAndContentStayInItsSlot() async throws {
    let controller = DockController(layout: DockLayout(root: .split(DockSplit(id: "root", axis: .horizontal, children: [
        .group(DockGroup(id: "mid", panels: ["transcript"])),
        .group(DockGroup(id: "right", panels: ["highlights", "terminal", "patches", "clickup"])),
    ], fractions: [0.8, 0.2]))))
    let frames = Frames()
    let content = DockContent(
        title: { $0 == "clickup" ? "ClickUp tasks due this week" : $0.capitalized },
        symbol: { _ in "pin" },
        view: { panel in
            AnyView(Color.clear.onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frames.content[panel] = $0 })
        }
    )
    let host = NSHostingView(rootView: DockView(controller: controller, content: content).frame(width: 1000, height: 600))
    host.frame = NSRect(x: 0, y: 0, width: 1000, height: 600)
    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    for _ in 0..<5 {
        try await Task.sleep(for: .milliseconds(20))
        host.layoutSubtreeIfNeeded()
    }

    let slot = try #require(controller.frames["right"])
    let shown = try #require(frames.content["highlights"])
    #expect(slot.maxX <= 1000.5, "the group runs past the window: \(slot)")
    #expect(slot.width < 220, "the group is wider than its fifth of the window: \(slot)")
    #expect(abs(shown.minX - slot.minX) < 0.5, "the content doesn't start at the group's edge: \(shown) in \(slot)")
    #expect(shown.maxX <= 1000.5, "the content runs past the window: \(shown)")
    let bar = try #require(controller.bars["right"])
    #expect(bar.maxX <= 1000.5, "the tabs run past the window: \(bar)")
}
