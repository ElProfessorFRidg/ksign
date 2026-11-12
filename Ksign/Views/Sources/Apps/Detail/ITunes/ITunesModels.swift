//
//  ITunesModels.swift
//  Ksign
//

import Foundation

// MARK: - Lookup API
struct ITunesLookupResponse: Decodable {
	let resultCount: Int
	let results: [ITunesApp]
}

struct ITunesApp: Decodable, Identifiable {
	var id: Int { trackId }
	
	let trackId: Int
	let trackName: String?
	let bundleId: String?
	let sellerName: String?
	let artistName: String?
	let description: String?
	let releaseNotes: String?
	let version: String?
	let screenshotUrls: [String]?
	let ipadScreenshotUrls: [String]?
	let averageUserRating: Double?
	let userRatingCount: Int?
	let averageUserRatingForCurrentVersion: Double?
	let userRatingCountForCurrentVersion: Int?
	let contentAdvisoryRating: String?
	let genres: [String]?
	let primaryGenreName: String?
	let formattedPrice: String?
	let minimumOsVersion: String?
	let languageCodesISO2A: [String]?
	let fileSizeBytes: String?
	let trackViewUrl: String?
	let sellerUrl: String?
	let currentVersionReleaseDate: String?
	
	var screenshotURLs: [URL] {
		(screenshotUrls ?? []).compactMap(URL.init(string:))
	}
	
	var ipadScreenshotURLs: [URL] {
		(ipadScreenshotUrls ?? []).compactMap(URL.init(string:))
	}
	
	var storeURL: URL? {
		trackViewUrl.flatMap(URL.init(string:))
	}
	
	var sizeBytes: Int64? {
		fileSizeBytes.flatMap { Int64($0) }
	}
	
	var languages: [String] {
		(languageCodesISO2A ?? []).compactMap {
			Locale.current.localizedString(forLanguageCode: $0.lowercased())?.capitalized
		}
	}
	
	var releaseDate: Date? {
		currentVersionReleaseDate.flatMap { ISO8601DateFormatter().date(from: $0) }
	}
}

// MARK: - Customer reviews (RSS)
struct ITunesReview: Identifiable {
	let id: String
	let author: String
	let title: String
	let content: String
	let rating: Int
	let version: String?
	let date: Date?
}

struct ITunesReviewsFeed: Decodable {
	let feed: Feed
	
	struct Label: Decodable { let label: String? }
	
	struct Entry: Decodable {
		let id: Label?
		let author: Author?
		let title: Label?
		let content: Label?
		let rating: Label?
		let version: Label?
		let updated: Label?
		
		struct Author: Decodable { let name: Label? }
		
		enum CodingKeys: String, CodingKey {
			case id, author, title, content, updated
			case rating = "im:rating"
			case version = "im:version"
		}
	}
	
	struct Feed: Decodable {
		let entry: [Entry]?
		
		// The feed returns a single object instead of an array when there is only one entry.
		init(from decoder: Decoder) throws {
			let container = try decoder.container(keyedBy: CodingKeys.self)
			if let many = try? container.decodeIfPresent([Entry].self, forKey: .entry) {
				entry = many
			} else if let one = try? container.decodeIfPresent(Entry.self, forKey: .entry) {
				entry = [one]
			} else {
				entry = nil
			}
		}
		
		enum CodingKeys: String, CodingKey { case entry }
	}
	
	var reviews: [ITunesReview] {
		let formatter = ISO8601DateFormatter()
		return (feed.entry ?? []).compactMap { entry in
			// The first entry of the feed can be the app itself, it has no rating.
			guard
				let rating = entry.rating?.label.flatMap(Int.init),
				let content = entry.content?.label
			else { return nil }
			return ITunesReview(
				id: entry.id?.label ?? UUID().uuidString,
				author: entry.author?.name?.label ?? "",
				title: entry.title?.label ?? "",
				content: content,
				rating: rating,
				version: entry.version?.label,
				date: entry.updated?.label.flatMap { formatter.date(from: $0) }
			)
		}
	}
}
