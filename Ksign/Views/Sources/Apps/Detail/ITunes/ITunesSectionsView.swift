//
//  ITunesSectionsView.swift
//  Ksign
//

import SwiftUI
import NimbleViews
import NukeUI

// MARK: - Ratings summary
struct ITunesRatingView: View {
	let app: ITunesApp
	
	var body: some View {
		if let rating = app.averageUserRating, let count = app.userRatingCount, count > 0 {
			NBSection(.localized("Ratings")) {
				HStack(alignment: .center, spacing: 16) {
					Text(verbatim: String(format: "%.1f", rating))
						.font(.system(size: 48, weight: .bold, design: .rounded))
					VStack(alignment: .leading, spacing: 4) {
						ITunesStarsView(rating: rating)
						Text(verbatim: .localized("%lld Ratings", arguments: count))
							.font(.footnote)
							.foregroundStyle(.secondary)
					}
					Spacer()
				}
			}
			Divider()
		}
	}
}

struct ITunesStarsView: View {
	let rating: Double
	
	var body: some View {
		HStack(spacing: 2) {
			ForEach(1...5, id: \.self) { star in
				Image(systemName: Double(star) <= rating.rounded(.down) ? "star.fill" : (Double(star) - 0.5 <= rating ? "star.leadinghalf.filled" : "star"))
					.foregroundStyle(.orange)
			}
		}
		.font(.subheadline)
	}
}

// MARK: - Reviews
struct ITunesReviewsView: View {
	let reviews: [ITunesReview]
	
	var body: some View {
		if !reviews.isEmpty {
			NBSection(.localized("Reviews")) {
				ScrollView(.horizontal, showsIndicators: false) {
					HStack(alignment: .top, spacing: 12) {
						ForEach(reviews.prefix(10)) { review in
							VStack(alignment: .leading, spacing: 6) {
								HStack {
									Text(review.title).font(.subheadline.weight(.semibold)).lineLimit(1)
									Spacer(minLength: 4)
									if let date = review.date {
										Text(date, style: .date).font(.caption2).foregroundStyle(.secondary)
									}
								}
								HStack {
									ITunesStarsView(rating: Double(review.rating))
									Spacer()
									Text(review.author).font(.caption).foregroundStyle(.secondary).lineLimit(1)
								}
								Text(review.content)
									.font(.footnote)
									.lineLimit(6)
									.frame(maxWidth: .infinity, alignment: .leading)
							}
							.padding()
							.frame(width: 280, height: 170, alignment: .topLeading)
							.background(
								RoundedRectangle(cornerRadius: 18, style: .continuous)
									.fill(Color(.quaternarySystemFill))
							)
						}
					}
					.padding(.horizontal)
				}
				.padding(.horizontal, -16)
			}
			Divider()
		}
	}
}

// MARK: - Extra information rows
struct ITunesInfoRows: View {
	let app: ITunesApp
	
	var body: some View {
		VStack(spacing: 12) {
			if let seller = app.sellerName ?? app.artistName {
				row(.localized("Seller"), seller)
			}
			if let genres = app.genres, !genres.isEmpty {
				row(.localized("Genres"), genres.joined(separator: ", "))
			}
			if let age = app.contentAdvisoryRating {
				row(.localized("Age Rating"), age)
			}
			if let price = app.formattedPrice {
				row(.localized("Price"), price)
			}
			if let minOS = app.minimumOsVersion {
				row(.localized("Requires iOS"), minOS)
			}
			if !app.languages.isEmpty {
				row(.localized("Languages"), app.languages.joined(separator: ", "))
			}
			if let url = app.storeURL {
				Link(.localized("View on the App Store"), destination: url)
					.frame(maxWidth: .infinity, alignment: .leading)
				Divider()
			}
		}
	}
	
	@ViewBuilder
	private func row(_ title: String, _ value: String) -> some View {
		LabeledContent(title, value: value)
		Divider()
	}
}
