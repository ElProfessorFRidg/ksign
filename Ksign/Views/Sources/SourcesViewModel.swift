//
//  SourcesViewModel.swift
//  Feather
//

import Foundation
import AltSourceKit
import SwiftUI
import NimbleJSON

@MainActor
final class SourcesViewModel: ObservableObject {
    static let shared = SourcesViewModel()

    typealias RepositoryDataHandler = Result<ASRepository, Error>

    private let _dataService = NBFetchService()
    private var _loadTask: Task<Void, Never>?

    @Published private(set) var isFinished = true
    @Published private(set) var revision = 0
    @Published private(set) var errors: [URL: String] = [:]
    @Published var sources: [AltSource: ASRepository] = [:]

    func fetchSources(_ fetchedSources: FetchedResults<AltSource>, refresh: Bool = false, batchSize: Int = 6) async {
        // Snapshot managed objects and URLs only on their UI context.
        let snapshot = Array(fetchedSources)
        let joinedExistingLoad = _loadTask != nil
        if let task = _loadTask {
            await task.value
        }

        let active = Set(snapshot)
        sources = sources.filter { active.contains($0.key) }
        let urls = Set(snapshot.compactMap(\.sourceURL))
        errors = errors.filter { urls.contains($0.key) }
        revision += 1

        // Callers joining a current refresh share its requests. Sources added
        // during that refresh are picked up as missing immediately afterwards.
        let reload = refresh && !joinedExistingLoad
        let needed = snapshot.filter { reload || sources[$0] == nil }
        guard !needed.isEmpty else { return }

        let task = Task {
            await self._load(needed, refresh: reload, concurrency: min(8, max(1, batchSize)))
        }
        _loadTask = task
        await task.value
    }

    private func _load(_ requested: [AltSource], refresh: Bool, concurrency: Int) async {
        isFinished = false
        defer {
            isFinished = true
            _loadTask = nil
        }

        // Keep previously loaded content visible, including when a refresh fails.
        // Duplicate URLs share one network request.
        let byURL = Dictionary(grouping: requested.filter { $0.sourceURL != nil }) { $0.sourceURL! }
        let urls = Array(byURL.keys)
        let service = _dataService

        await withTaskGroup(of: (URL, ASRepository?, String?).self) { group in
            var nextIndex = 0
            func enqueue(_ url: URL) {
                group.addTask {
                    do {
                        let repository: ASRepository = try await service.fetch(from: url, refresh: refresh)
                        return (url, repository, nil)
                    } catch {
                        return (url, nil, error.localizedDescription)
                    }
                }
            }

            while nextIndex < min(concurrency, urls.count) {
                enqueue(urls[nextIndex])
                nextIndex += 1
            }

            // Start another source as soon as any finishes, rather than waiting
            // for the slowest member of a fixed batch. Publish results immediately.
            for await (url, repository, error) in group {
                if let repository {
                    for source in byURL[url] ?? [] {
                        sources[source] = repository
                    }
                    errors.removeValue(forKey: url)
                    revision += 1
                } else if let error {
                    errors[url] = error
                }
                if nextIndex < urls.count {
                    enqueue(urls[nextIndex])
                    nextIndex += 1
                }
            }
        }
    }
}

