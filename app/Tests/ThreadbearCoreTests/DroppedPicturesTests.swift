import XCTest
@testable import ThreadbearCore

final class DroppedPicturesTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("dropped-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func file(_ relative: String) throws -> URL {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("png".utf8).write(to: url)
        return url
    }

    /// A screenshot dragged from macOS's floating thumbnail is a file in
    /// TemporaryItems, which only the app the drag went to may open, so
    /// the app copies it out, keeping its name, for the runner to read.
    func testAThumbnailDragIsCopiedOutUnderItsName() throws {
        let src = try file("T/TemporaryItems/NSIRD_screencaptureui_abc/Screenshot 2026-11-07 at 15.48.42.png")
        let out = root.appendingPathComponent("paste", isDirectory: true)
        let copy = DroppedPictures.readable(src, copyingInto: out)
        XCTAssertNotEqual(copy.path, src.path)
        XCTAssertEqual(copy.lastPathComponent, "Screenshot 2026-11-07 at 15.48.42.png")
        XCTAssertTrue(copy.path.hasPrefix(out.path))
        XCTAssertEqual(try Data(contentsOf: copy), Data("png".utf8))
    }

    func testAFileAnywhereElseStaysWhereItIs() throws {
        let src = try file("Desktop/Screenshot.png")
        let out = root.appendingPathComponent("paste", isDirectory: true)
        XCTAssertEqual(DroppedPictures.readable(src, copyingInto: out), src)
        XCTAssertFalse(FileManager.default.fileExists(atPath: out.path))
    }

    func testAFailedCopyFallsBackToTheOriginal() {
        let gone = root.appendingPathComponent("T/TemporaryItems/x/gone.png")
        XCTAssertEqual(DroppedPictures.readable(gone, copyingInto: root.appendingPathComponent("paste")), gone)
    }
}
