//
//  NativeTextView+ImageDrop.swift
//  MarkdownEngine
//
//  Images dropped on the editor become markdown, never rich-text
//  attachments: the embedder's `onDropImage` (else `onPasteImage`) turns
//  the dragged pasteboard into embed lines, inserted as their own block
//  at the nearest line boundary to the drop. File promises (Photos, some
//  browsers) are received into a temporary folder first and handed over
//  as file URLs on a private pasteboard.
//

import AppKit
import UniformTypeIdentifiers

extension NativeTextView {
    /// The hook a drop goes through: the drop-specific one, else paste's.
    var imageDropHandler: ((NSPasteboard) -> String?)? { onDropImage ?? onPasteImage }

    override var acceptableDragTypes: [NSPasteboard.PasteboardType] {
        var types = super.acceptableDragTypes
        guard isEditable, imageDropHandler != nil else { return types }
        let promised = NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
        for type in [NSPasteboard.PasteboardType.fileURL, .png, .tiff] + promised where !types.contains(type) {
            types.append(type)
        }
        return types
    }

    override func dragOperation(for dragInfo: any NSDraggingInfo, type: NSPasteboard.PasteboardType) -> NSDragOperation {
        if isEditable, imageDropHandler != nil, Self.carriesImage(dragInfo.draggingPasteboard) { return .copy }
        return super.dragOperation(for: dragInfo, type: type)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard isEditable, let handler = imageDropHandler, Self.carriesImage(sender.draggingPasteboard) else {
            return super.performDragOperation(sender)
        }
        let location = imageDropLocation(for: convert(sender.draggingLocation, from: nil))
        let pasteboard = sender.draggingPasteboard

        // Files and image data are read now, while the drag still grants access.
        if let embed = handler(pasteboard), !embed.isEmpty {
            insertDroppedEmbed(embed, at: location)
            return true
        }
        let promises = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self]) as? [NSFilePromiseReceiver] ?? []
        guard !promises.isEmpty else { return super.performDragOperation(sender) }
        receivePromisedImages(promises) { [weak self] files in
            guard let self, !files.isEmpty else { return }
            let privateBoard = NSPasteboard(name: NSPasteboard.Name("MarkdownEngine.drop.\(UUID().uuidString)"))
            privateBoard.clearContents()
            privateBoard.writeObjects(files as [NSURL])
            defer { privateBoard.releaseGlobally() }
            if let embed = handler(privateBoard), !embed.isEmpty {
                self.insertDroppedEmbed(embed, at: location)
            }
        }
        return true
    }

    /// The drop point moved to the nearest line boundary, so a dropped image
    /// never splits a line of text.
    func imageDropLocation(for point: NSPoint) -> Int {
        let ns = string as NSString
        let index = min(max(0, characterIndexForInsertion(at: point)), ns.length)
        guard ns.length > 0 else { return 0 }
        let paragraph = ns.paragraphRange(for: NSRange(location: min(index, ns.length - 1), length: 0))
        var end = NSMaxRange(paragraph)
        if end > paragraph.location, end <= ns.length, ns.character(at: end - 1) == 0x0A { end -= 1 }
        if index <= paragraph.location || index >= end { return index }
        return index - paragraph.location < end - index ? paragraph.location : end
    }

    private func insertDroppedEmbed(_ embed: String, at location: Int) {
        let clamped = min(location, (string as NSString).length)
        window?.makeFirstResponder(self)
        setSelectedRange(NSRange(location: clamped, length: 0))
        insertBlockEmbed(embed)
    }

    /// Promised files land in a fresh temporary folder; `done` gets the image
    /// files among them, on the main queue.
    private func receivePromisedImages(_ promises: [NSFilePromiseReceiver], done: @escaping @MainActor ([URL]) -> Void) {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarkdownEngine-drop-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let queue = OperationQueue()
        queue.qualityOfService = .userInitiated
        let group = DispatchGroup()
        let lock = NSLock()
        nonisolated(unsafe) var files: [URL] = []
        for promise in promises {
            group.enter()
            promise.receivePromisedFiles(atDestination: folder, options: [:], operationQueue: queue) { url, error in
                if error == nil, Self.isImageFile(url) {
                    lock.lock(); files.append(url); lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            lock.lock(); let received = files; lock.unlock()
            MainActor.assumeIsolated { done(received) }
        }
    }

    /// Whether a drag brings an image: an image file, image data with no
    /// text of its own, or a promise of an image file.
    static func carriesImage(_ pasteboard: NSPasteboard) -> Bool {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            return urls.contains(where: isImageFile)
        }
        if let promises = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self]) as? [NSFilePromiseReceiver],
           promises.contains(where: { $0.fileTypes.contains { UTType($0)?.conforms(to: .image) == true } }) {
            return true
        }
        let types = pasteboard.types ?? []
        return types.contains(.png) || types.contains(.tiff)
    }

    static func isImageFile(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true
    }
}
