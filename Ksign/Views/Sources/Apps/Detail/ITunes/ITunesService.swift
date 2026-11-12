//
//  ITunesService.swift
//  Ksign
//

import Foundation

// MARK: - ITunesService
actor ITunesService {
	static let shared = ITunesService()
	
	private var _appCache: [String: ITunesApp?] = [:]
	private var _reviewsCache: [Int: [ITunesReview]] = [:]
	
	private var _countries: [String] {
		let local = Locale.current.region?.identifier.lowercased()
		return [local, "us"].compactMap { $0 }.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
	}
	
	/// Looks an app up on the App Store from its bundle identifier.
	func lookup(bundleId: String) async -> (app: ITunesApp, country: String)? {
		for country in _countries {
			let key = "\(country)/\(bundleId)"
			if let cached = _appCache[key] {
				if let cached { return (cached, country) }
				continue
			}
			
			var components = URLComponents(string: "https://itunes.apple.com/lookup")!
			components.queryItems = [
				URLQueryItem(name: "bundleId", value: bundleId),
				URLQueryItem(name: "country", value: country)
			]
			
			var found: ITunesApp?
			if
				let url = components.url,
				let (data, _) = try? await URLSession.shared.data(from: url),
				let response = try? JSONDecoder().decode(ITunesLookupResponse.self, from: data)
			{
				found = response.results.first
			}
			_appCache[key] = .some(found)
			if let found { return (found, country) }
		}
		return nil
	}
	
	func reviews(trackId: Int, country: String) async -> [ITunesReview] {
		if let cached = _reviewsCache[trackId] { return cached }
		guard let url = URL(string: "https://itunes.apple.com/\(country)/rss/customerreviews/page=1/id=\(trackId)/sortby=mostrecent/json") else {
			return []
		}
		guard
			let (data, _) = try? await URLSession.shared.data(from: url),
			let feed = try? JSONDecoder().decode(ITunesReviewsFeed.self, from: data)
		else { return [] }
		let reviews = feed.reviews
		_reviewsCache[trackId] = reviews
		return reviews
	}
}

// MARK: - ITunesLoader
@MainActor
final class ITunesLoader: ObservableObject {
	@Published private(set) var app: ITunesApp?
	@Published private(set) var reviews: [ITunesReview] = []
	@Published private(set) var isLoading = false
	
	func load(bundleId: String?) async {
		guard app == nil, let bundleId, !bundleId.isEmpty else { return }
		isLoading = true
		defer { isLoading = false }
		
		guard let (found, country) = await ITunesService.shared.lookup(bundleId: bundleId) else { return }
		app = found
		reviews = await ITunesService.shared.reviews(trackId: found.trackId, country: country)
	}
}
