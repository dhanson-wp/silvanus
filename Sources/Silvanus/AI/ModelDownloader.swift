import Foundation
import SilvanusKit

/// Why a download didn't finish, in plain words.
nonisolated enum ModelDownloadError: LocalizedError, Equatable {
    case noRoom(String)
    case refused(Int)
    case interrupted
    case failedCheck
    case cannotSave

    var errorDescription: String? {
        switch self {
        case let .noRoom(message): message
        case let .refused(status): "The download isn't available right now (error \(status)). Try again later."
        case .interrupted: "The download stopped before it finished. Check your connection, then retry."
        case .failedCheck: "The file didn't arrive whole, so it was deleted. Retry to download it again."
        case .cannotSave: "Unable to save the file in the models folder."
        }
    }
}

/// How the bytes arrive. The app uses `live` (the network); checks use `fixture`, so no
/// check ever downloads anything.
nonisolated struct ModelTransport: Sendable {
    /// The start of a server's answer.
    struct Head: Sendable {
        var status: Int
        var contentRange: String?
    }

    /// Asks for `url` from byte `offset` on. Calls `head` once with the answer, then `body`
    /// with each piece in order; either one throwing stops the request with that error.
    var fetch: @Sendable (_ url: URL, _ offset: Int64, _ head: @escaping @Sendable (Head) throws -> Void,
                          _ body: @escaping @Sendable (Data) throws -> Void) async throws -> Void

    /// The network. Every request, a resumed one too, goes to the model's own address and
    /// follows its redirect afresh: the address behind the redirect is signed and expires.
    static let live = ModelTransport { url, offset, head, body in
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        if let range = ModelDownloadRules.rangeHeader(offset: offset) { request.setValue(range, forHTTPHeaderField: "Range") }
        let receiver = Receiver(head: head, body: body)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.urlCache = nil
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: configuration, delegate: receiver, delegateQueue: queue)
        let task = session.dataTask(with: request)
        defer { session.finishTasksAndInvalidate() }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                receiver.continuation = continuation
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }

    /// Serves `data` from memory, honoring the offset like a server that supports ranges.
    /// `stopAfter` drops the connection once that many bytes of one request were sent;
    /// `pause` waits between pieces. `log` records each request's offset.
    static func fixture(_ data: Data, piece: Int = 512, pause: Duration = .zero, stopAfter: Int? = nil,
                        log: FixtureLog = FixtureLog()) -> ModelTransport {
        ModelTransport { _, offset, head, body in
            log.add(offset)
            guard offset < Int64(data.count) else {
                try head(Head(status: 416, contentRange: "bytes */\(data.count)"))
                return
            }
            let start = Int(offset)
            try head(Head(status: start > 0 ? 206 : 200,
                          contentRange: start > 0 ? "bytes \(start)-\(data.count - 1)/\(data.count)" : nil))
            var sent = 0
            while start + sent < data.count {
                try Task.checkCancellation()
                if pause > .zero { try await Task.sleep(for: pause) }
                let end = min(start + sent + piece, data.count)
                try body(data.subdata(in: (start + sent)..<end))
                sent = end - start
                if let stopAfter, sent >= stopAfter, end < data.count { throw URLError(.networkConnectionLost) }
            }
        }
    }

    /// The offsets a fixture was asked for, in order.
    nonisolated final class FixtureLog: @unchecked Sendable {
        private let lock = NSLock()
        private var seen: [Int64] = []
        var offsets: [Int64] { lock.withLock { seen } }
        func add(_ offset: Int64) { lock.withLock { seen.append(offset) } }
    }

    /// One request's delegate. Its callbacks arrive one at a time on the session's queue,
    /// so a piece is on disk before the next is read from the network.
    private nonisolated final class Receiver: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        let head: @Sendable (Head) throws -> Void
        let body: @Sendable (Data) throws -> Void
        var continuation: CheckedContinuation<Void, Error>?
        private var failure: Error?

        init(head: @escaping @Sendable (Head) throws -> Void, body: @escaping @Sendable (Data) throws -> Void) {
            self.head = head
            self.body = body
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
            let http = response as? HTTPURLResponse
            do {
                try head(Head(status: http?.statusCode ?? 0, contentRange: http?.value(forHTTPHeaderField: "Content-Range")))
                completionHandler(.allow)
            } catch {
                failure = error
                completionHandler(.cancel)
            }
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            guard failure == nil else { return }
            do {
                try body(data)
            } catch {
                failure = error
                dataTask.cancel()
            }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            let result: Result<Void, Error> = (failure ?? error).map { .failure($0) } ?? .success(())
            continuation?.resume(with: result)
            continuation = nil
        }
    }
}

/// Downloads a catalog model into a folder: to `<file>.download` first, picking up where
/// an earlier try stopped, then checks the size and SHA-256 before giving the file its
/// real name. A file that fails the check is deleted. Runs off the main thread.
nonisolated enum ModelDownloader {
    enum Event: Sendable, Equatable {
        /// This many bytes are on disk.
        case progress(Int64)
        /// Everything arrived; the checksum is being worked out.
        case checking
    }

    /// The free space on the disk that holds `folder`, counting what macOS can clear.
    static let freeSpace: @Sendable (URL) -> Int64? = { folder in
        (try? folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage
    }

    static func partialBytes(_ model: CatalogModel, in folder: URL) -> Int64 {
        let path = folder.appendingPathComponent(model.partialName).path
        return ((try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? NSNumber)?.int64Value ?? 0
    }

    /// The finished file's address. Throws `ModelDownloadError`, or `CancellationError`
    /// when the task was cancelled (what arrived so far is kept, to resume).
    @concurrent
    static func download(_ model: CatalogModel, into folder: URL, transport: ModelTransport = .live,
                         freeSpace: @Sendable (URL) -> Int64? = ModelDownloader.freeSpace,
                         progressStep: Int64 = 4 << 20,
                         onEvent: @escaping @Sendable (Event) -> Void) async throws -> URL {
        let files = FileManager.default
        let final = folder.appendingPathComponent(model.fileName)
        let partial = folder.appendingPathComponent(model.partialName)
        if files.fileExists(atPath: final.path) { return final }
        do {
            try files.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            throw ModelDownloadError.cannotSave
        }

        var startedOver = false
        while true {
            let offset = ModelDownloadRules.resumeOffset(partialBytes: partialBytes(model, in: folder), total: model.bytes)
            if offset == 0 { try? files.removeItem(at: partial) }
            if let message = ModelDownloadRules.noRoom(total: model.bytes, partialBytes: offset, free: freeSpace(folder)) {
                throw ModelDownloadError.noRoom(message)
            }
            onEvent(.progress(offset))
            guard offset < model.bytes else { break }
            let writer = Writer(file: partial, offset: offset, total: model.bytes, step: progressStep, onEvent: onEvent)
            do {
                try await transport.fetch(model.url, offset, { try writer.begin($0) }, { try writer.write($0) })
                writer.close()
                break
            } catch {
                writer.close()
                if Task.isCancelled || error is CancellationError { throw CancellationError() }
                if error is Writer.Discard, !startedOver {
                    // The server can't continue this partial file: once, start it over.
                    startedOver = true
                    try? files.removeItem(at: partial)
                    continue
                }
                if let known = error as? ModelDownloadError {
                    if known == .failedCheck { try? files.removeItem(at: partial) }
                    throw known
                }
                throw ModelDownloadError.interrupted
            }
        }

        let size = partialBytes(model, in: folder)
        guard size == model.bytes else {
            if size > model.bytes {
                try? files.removeItem(at: partial)
                throw ModelDownloadError.failedCheck
            }
            throw ModelDownloadError.interrupted
        }
        onEvent(.checking)
        let hash = ModelDownloadRules.sha256(of: partial, keepGoing: { !Task.isCancelled })
        if Task.isCancelled { throw CancellationError() }
        guard hash == model.sha256.lowercased() else {
            try? files.removeItem(at: partial)
            throw ModelDownloadError.failedCheck
        }
        do {
            // A rename inside one folder: the file appears whole or not at all.
            try files.moveItem(at: partial, to: final)
        } catch {
            throw ModelDownloadError.cannotSave
        }
        return final
    }

    /// Writes one request's pieces to the partial file. Used from one queue at a time.
    private nonisolated final class Writer: @unchecked Sendable {
        /// The server can't continue the partial file.
        struct Discard: Error {}

        private let file: URL
        private let offset: Int64
        private let total: Int64
        private let step: Int64
        private let onEvent: @Sendable (Event) -> Void
        private var handle: FileHandle?
        private var done: Int64 = 0
        private var reported: Int64 = 0

        init(file: URL, offset: Int64, total: Int64, step: Int64, onEvent: @escaping @Sendable (Event) -> Void) {
            self.file = file
            self.offset = offset
            self.total = total
            self.step = step
            self.onEvent = onEvent
        }

        func begin(_ head: ModelTransport.Head) throws {
            switch ModelDownloadRules.start(status: head.status, offset: offset, contentRange: head.contentRange) {
            case .append:
                done = offset
            case .restart:
                try? FileManager.default.removeItem(at: file)
                done = 0
            case .discard:
                throw Discard()
            case let .refuse(status):
                throw ModelDownloadError.refused(status)
            }
            if !FileManager.default.fileExists(atPath: file.path) {
                guard FileManager.default.createFile(atPath: file.path, contents: nil) else { throw ModelDownloadError.cannotSave }
            }
            guard let handle = try? FileHandle(forWritingTo: file), (try? handle.seekToEnd()) != nil else {
                throw ModelDownloadError.cannotSave
            }
            self.handle = handle
            reported = done
            onEvent(.progress(done))
        }

        func write(_ data: Data) throws {
            guard let handle else { throw ModelDownloadError.cannotSave }
            // More than the file's size can't be the file.
            guard done + Int64(data.count) <= total else { throw ModelDownloadError.failedCheck }
            do {
                try handle.write(contentsOf: data)
            } catch {
                throw ModelDownloadError.cannotSave
            }
            done += Int64(data.count)
            if done - reported >= step || done == total {
                reported = done
                onEvent(.progress(done))
            }
        }

        func close() {
            try? handle?.close()
            handle = nil
        }
    }
}

/// Silvanus's downloaded models, and any download under way. It lives in the app's state,
/// not in a view, so a download keeps going when Settings or the window closes; one cut
/// off by a quit leaves its partial file, and Continue picks it up.
@Observable
final class SummaryModels {
    /// Where one catalog model stands.
    enum State: Equatable {
        case notDownloaded
        /// Part of it is on disk and nothing is downloading: Continue fetches the rest.
        case partial(Int64)
        case downloading(Int64)
        case checking
        case downloaded
        case failed(String)
    }

    /// The models folder: `~/Library/Application Support/Silvanus/models`, from the home
    /// directory at runtime. Test, snapshot, and self-test runs use a folder in their
    /// scratch store instead, so they never see or change the real one.
    static var defaultFolder: URL {
        if AppDefaults.isTest {
            let root = Store.isOverridden ? Store.root : FileManager.default.temporaryDirectory.appending(path: "Silvanus-test")
            return root.appending(path: "models", directoryHint: .isDirectory)
        }
        return LocalModelFile.folder(home: FileManager.default.homeDirectoryForCurrentUser)
    }

    let folder: URL
    /// The models on offer. The self-test swaps in a tiny made-up one.
    var catalog: [CatalogModel]
    /// This Mac's memory, which picks the recommended model. Snapshots fix it.
    var physicalMemory: UInt64
    @ObservationIgnored var transport: ModelTransport = .live
    @ObservationIgnored var freeSpace: @Sendable (URL) -> Int64? = ModelDownloader.freeSpace
    @ObservationIgnored var progressStep: Int64 = 4 << 20
    /// Called when a download ends or a file is removed.
    @ObservationIgnored var changed: (() -> Void)?
    /// Snapshots stage each model's state here; then nothing reads the disk or the network.
    var staged: [String: State]?

    private var active: [String: State] = [:]
    /// Goes up when the folder's files change, so views read the disk again.
    private var revision = 0
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]

    init(folder: URL = SummaryModels.defaultFolder, catalog: [CatalogModel] = LocalModelCatalog.all,
         physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory) {
        self.folder = folder
        self.catalog = catalog
        self.physicalMemory = physicalMemory
    }

    /// The model this Mac should get.
    var recommended: CatalogModel? { LocalModelCatalog.recommended(physicalMemory: physicalMemory, from: catalog) }
    /// The catalog with the recommended model first: the order a downloaded one is picked in.
    var ordered: [CatalogModel] { LocalModelCatalog.ordered(physicalMemory: physicalMemory, from: catalog) }

    func state(of model: CatalogModel) -> State {
        if let staged { return staged[model.id] ?? .notDownloaded }
        _ = revision
        if let state = active[model.id] { return state }
        if FileManager.default.fileExists(atPath: folder.appendingPathComponent(model.fileName).path) { return .downloaded }
        let partial = ModelDownloader.partialBytes(model, in: folder)
        return partial > 0 ? .partial(partial) : .notDownloaded
    }

    /// The model file in use: `chosen` when it exists, else the first downloaded one.
    func found(chosen: String?) -> LocalModelFile.Found? {
        if let staged {
            return ordered.first { staged[$0.id] == .downloaded }
                .map { LocalModelFile.Found(url: folder.appendingPathComponent($0.fileName), source: .downloaded, title: $0.name) }
        }
        _ = revision
        return LocalModelFile.find(chosen: chosen, folder: folder, models: ordered)
    }

    /// True when a downloaded model is there to go back to.
    var hasDownloaded: Bool {
        if let staged { return staged.values.contains(.downloaded) }
        _ = revision
        return LocalModelFile.downloaded(in: folder, models: ordered) != nil
    }

    /// True while any model downloads or is being checked.
    var isBusy: Bool { !tasks.isEmpty }

    /// Starts the download, or picks up a partial one. Also what Continue and Retry do.
    @discardableResult
    func download(_ model: CatalogModel) -> Task<Void, Never>? {
        guard staged == nil else { return nil }
        if let running = tasks[model.id] { return running }
        active[model.id] = .downloading(ModelDownloader.partialBytes(model, in: folder))
        let id = model.id
        let folder = folder, transport = transport, freeSpace = freeSpace, step = progressStep
        let work = Task { [weak self] in
            do {
                _ = try await ModelDownloader.download(model, into: folder, transport: transport, freeSpace: freeSpace,
                                                       progressStep: step) { event in
                    Task { @MainActor in self?.apply(event, to: id) }
                }
                self?.active[id] = nil
            } catch is CancellationError {
                self?.active[id] = nil
            } catch {
                self?.active[id] = .failed(error.localizedDescription)
            }
            self?.tasks[id] = nil
            self?.revision += 1
            self?.changed?()
        }
        tasks[id] = work
        return work
    }

    /// Stops the download. What arrived stays, so Continue goes on from there.
    func cancel(_ model: CatalogModel) {
        tasks[model.id]?.cancel()
    }

    /// Deletes the model's file, and any partial one.
    func remove(_ model: CatalogModel) {
        guard staged == nil, tasks[model.id] == nil else { return }
        for name in [model.fileName, model.partialName] {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
        active[model.id] = nil
        revision += 1
        changed?()
    }

    private func apply(_ event: ModelDownloader.Event, to id: String) {
        // An update that lands after the download ended is stale.
        guard tasks[id] != nil else { return }
        switch event {
        case let .progress(bytes):
            if active[id] != .checking { active[id] = .downloading(bytes) }
        case .checking:
            active[id] = .checking
        }
    }
}
