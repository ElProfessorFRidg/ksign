//
//  ChunkedDownloader.swift
//  Ksign
//

import Foundation

// MARK: - Probe
struct ChunkedDownloadProbe {
	/// URL after redirects (CDN), so every chunk hits the final host directly.
	let url: URL
	let totalBytes: Int64
	let etag: String?
	let suggestedFilename: String?
}

enum ChunkedDownloadError: LocalizedError {
	case unexpectedResponse
	case incompleteFile
	
	var errorDescription: String? {
		switch self {
		case .unexpectedResponse: "The server did not honor the range request."
		case .incompleteFile: "The downloaded file is incomplete."
		}
	}
}

// MARK: - ChunkedDownloader
/// Downloads a file as several byte ranges in parallel (like a download manager)
/// and writes them straight into one pre-allocated file.
/// All state is only touched from `_queue`, the serial delegate queue.
final class ChunkedDownloader: NSObject, URLSessionDataDelegate, @unchecked Sendable {
	/// Files smaller than this are not worth splitting.
	static let minimumSize: Int64 = 8 * 1024 * 1024
	private static let maxConnections = 8
	private static let maxRetries = 4
	
	private struct Chunk {
		let start: Int64
		let end: Int64 // inclusive
		var received: Int64 = 0
		var attempts = 0
		var nextOffset: Int64 { start + received }
		var isComplete: Bool { nextOffset > end }
	}
	
	/// (bytes received, total bytes). Called from the delegate queue.
	var onProgress: ((Int64, Int64) -> Void)?
	/// Called once, from the delegate queue, with the finished file or an error.
	var onCompletion: ((Result<URL, Error>) -> Void)?
	
	let probe: ChunkedDownloadProbe
	let fileURL: URL
	
	private let _queue = OperationQueue()
	private var _session: URLSession!
	private var _chunks: [Chunk] = []
	private var _pending: [Int] = []
	private var _active: [Int: Int] = [:] // task identifier -> chunk index
	private var _handle: FileHandle?
	private var _received: Int64 = 0
	private var _lastReport = Date.distantPast
	private var _finished = false
	
	init(probe: ChunkedDownloadProbe) {
		self.probe = probe
		self.fileURL = FileManager.default.temporaryDirectory
			.appendingPathComponent("FeatherChunks_\(UUID().uuidString).part")
		super.init()
		
		_queue.maxConcurrentOperationCount = 1
		_queue.qualityOfService = .userInitiated
		
		let configuration = URLSessionConfiguration.default
		configuration.httpMaximumConnectionsPerHost = Self.maxConnections
		configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
		configuration.urlCache = nil
		configuration.timeoutIntervalForRequest = 30
		_session = URLSession(configuration: configuration, delegate: self, delegateQueue: _queue)
	}
	
	// MARK: Probe
	/// Asks the server for the first byte only. Returns nil when ranges are not
	/// supported or the file is too small, the caller then falls back to a normal download.
	static func probe(url: URL) async -> ChunkedDownloadProbe? {
		guard url.scheme == "https" || url.scheme == "http" else { return nil }
		
		let delegate = ProbeDelegate()
		let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
		defer { session.finishTasksAndInvalidate() }
		
		var request = URLRequest(url: url)
		request.timeoutInterval = 15
		request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
		request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
		
		let response: HTTPURLResponse? = await withCheckedContinuation { continuation in
			delegate.set(continuation)
			session.dataTask(with: request).resume()
		}
		
		guard
			let response,
			response.statusCode == 206,
			let contentRange = response.value(forHTTPHeaderField: "Content-Range"),
			let totalString = contentRange.split(separator: "/").last,
			let total = Int64(totalString),
			total >= minimumSize
		else { return nil }
		
		return ChunkedDownloadProbe(
			url: response.url ?? url,
			totalBytes: total,
			etag: response.value(forHTTPHeaderField: "ETag"),
			suggestedFilename: response.suggestedFilename
		)
	}
	
	// MARK: Control
	func start() {
		_queue.addOperation { self._start() }
	}
	
	func cancel() {
		_queue.addOperation {
			guard !self._finished else { return }
			self._finished = true
			self._cleanUp(removeFile: true)
		}
	}
	
	// MARK: Private (delegate queue only)
	private func _start() {
		let total = probe.totalBytes
		do {
			FileManager.default.createFile(atPath: fileURL.path, contents: nil)
			let handle = try FileHandle(forWritingTo: fileURL)
			try handle.truncate(atOffset: UInt64(total))
			_handle = handle
		} catch {
			_complete(.failure(error))
			return
		}
		
		// Small chunks keep every connection busy until the end, so a slow one never holds everything back.
		let chunkSize = min(8 * 1024 * 1024, max(1024 * 1024, total / 32))
		var offset: Int64 = 0
		while offset < total {
			let end = min(offset + chunkSize - 1, total - 1)
			_chunks.append(Chunk(start: offset, end: end))
			offset = end + 1
		}
		_pending = Array(_chunks.indices)
		_pump()
	}
	
	private func _pump() {
		while !_finished, _active.count < Self.maxConnections, !_pending.isEmpty {
			_startTask(for: _pending.removeFirst())
		}
	}
	
	private func _startTask(for index: Int) {
		let chunk = _chunks[index]
		var request = URLRequest(url: probe.url)
		request.setValue("bytes=\(chunk.nextOffset)-\(chunk.end)", forHTTPHeaderField: "Range")
		request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
		if let etag = probe.etag, !etag.hasPrefix("W/") {
			// If the file changed meanwhile the server answers 200 and we fall back.
			request.setValue(etag, forHTTPHeaderField: "If-Range")
		}
		let task = _session.dataTask(with: request)
		_active[task.taskIdentifier] = index
		task.resume()
	}
	
	private func _report(force: Bool = false) {
		let now = Date()
		guard force || now.timeIntervalSince(_lastReport) > 0.1 else { return }
		_lastReport = now
		onProgress?(_received, probe.totalBytes)
	}
	
	private func _complete(_ result: Result<URL, Error>) {
		guard !_finished else { return }
		_finished = true
		if case .failure = result {
			_cleanUp(removeFile: true)
		} else {
			_cleanUp(removeFile: false)
		}
		onCompletion?(result)
	}
	
	private func _cleanUp(removeFile: Bool) {
		try? _handle?.close()
		_handle = nil
		_session.invalidateAndCancel()
		if removeFile {
			try? FileManager.default.removeItem(at: fileURL)
		}
	}
	
	private func _checkDone() {
		guard _pending.isEmpty, _active.isEmpty, _chunks.allSatisfy(\.isComplete) else { return }
		_report(force: true)
		try? _handle?.synchronize()
		let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
		let size = (attributes?[.size] as? NSNumber)?.int64Value
		if size == probe.totalBytes {
			try? _handle?.close()
			_handle = nil
			_complete(.success(fileURL))
		} else {
			_complete(.failure(ChunkedDownloadError.incompleteFile))
		}
	}
	
	// MARK: URLSessionDataDelegate
	func urlSession(
		_ session: URLSession,
		dataTask: URLSessionDataTask,
		didReceive response: URLResponse,
		completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
	) {
		guard
			(response as? HTTPURLResponse)?.statusCode == 206,
			_active[dataTask.taskIdentifier] != nil
		else {
			completionHandler(.cancel)
			_complete(.failure(ChunkedDownloadError.unexpectedResponse))
			return
		}
		completionHandler(.allow)
	}
	
	func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
		guard !_finished, let index = _active[dataTask.taskIdentifier], let handle = _handle else { return }
		
		// Never write past the end of the requested range.
		let remaining = _chunks[index].end - _chunks[index].nextOffset + 1
		let data = data.count > remaining ? data.prefix(Int(max(remaining, 0))) : data
		guard !data.isEmpty else { return }
		
		do {
			try handle.seek(toOffset: UInt64(_chunks[index].nextOffset))
			try handle.write(contentsOf: data)
		} catch {
			_complete(.failure(error))
			return
		}
		_chunks[index].received += Int64(data.count)
		_received += Int64(data.count)
		_report()
	}
	
	func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
		guard !_finished, let index = _active.removeValue(forKey: task.taskIdentifier) else { return }
		
		if error == nil, _chunks[index].isComplete {
			_pump()
			_checkDone()
			return
		}
		
		// Network hiccup or short answer: retry only what is missing, with a short backoff.
		_chunks[index].attempts += 1
		guard _chunks[index].attempts <= Self.maxRetries else {
			_complete(.failure(error ?? ChunkedDownloadError.incompleteFile))
			return
		}
		_pending.insert(index, at: 0)
		let delay = 0.5 * Double(_chunks[index].attempts)
		DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
			self?._queue.addOperation { self?._pump() }
		}
	}
}

// MARK: - ProbeDelegate
private final class ProbeDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
	private let _lock = NSLock()
	private var _continuation: CheckedContinuation<HTTPURLResponse?, Never>?
	
	func set(_ continuation: CheckedContinuation<HTTPURLResponse?, Never>) {
		_lock.lock(); defer { _lock.unlock() }
		_continuation = continuation
	}
	
	private func _resume(_ response: HTTPURLResponse?) {
		_lock.lock()
		let continuation = _continuation
		_continuation = nil
		_lock.unlock()
		continuation?.resume(returning: response)
	}
	
	// Headers are enough, cancel before any body is downloaded.
	func urlSession(
		_ session: URLSession,
		dataTask: URLSessionDataTask,
		didReceive response: URLResponse,
		completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
	) {
		completionHandler(.cancel)
		_resume(response as? HTTPURLResponse)
	}
	
	func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
		_resume(nil)
	}
}
