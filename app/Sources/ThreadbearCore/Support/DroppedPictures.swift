import Foundation

/// Pictures pasted or dropped as files go to the runner by path, and the
/// runner opens them itself. One macOS keeps in a TemporaryItems folder
/// (a screenshot dragged from its floating thumbnail) only the app the
/// drag went to may open: the runner gets "Operation not permitted" and
/// says it's not a supported image. So the app copies those out first,
/// while the drag still gives it access, under the same name.
public enum DroppedPictures {
    /// The app's own temp folder for pictures it hands the runner (pasted
    /// screenshots and dragged thumbnails).
    public static var folder: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("threadbear-paste", isDirectory: true)
    }

    /// `url`, or a copy of it in `folder` the runner can open. The original
    /// when it isn't somewhere only this app may read, or the copy fails.
    public static func readable(_ url: URL, copyingInto folder: URL = folder) -> URL {
        guard url.isFileURL, url.pathComponents.contains("TemporaryItems") else { return url }
        let dir = folder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let copy = dir.appendingPathComponent(url.lastPathComponent)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: url, to: copy)
            return copy
        } catch {
            try? FileManager.default.removeItem(at: dir)
            return url
        }
    }
}
