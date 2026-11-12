//
//  SourceNewsDetailView.swift
//  Ksign
//

import SwiftUI
import AltSourceKit
import NukeUI

// MARK: - SourceNewsDetailView
/// Full content of a news item: image, title, date, caption and its actions.
struct SourceNewsDetailView: View {
	@Environment(\.dismiss) private var dismiss
	
	let news: ASRepository.News
	/// The app the news points to, when it exists in the source.
	let app: ASRepository.App?
	var onOpenApp: () -> Void
	
	var body: some View {
		NavigationStack {
			ScrollView {
				VStack(alignment: .leading, spacing: 16) {
					_header
					
					VStack(alignment: .leading, spacing: 8) {
						Text(news.title)
							.font(.title2.weight(.bold))
						
						if let date = news.date?.date {
							Text(date, style: .date)
								.font(.subheadline)
								.foregroundStyle(.secondary)
						}
						
						if !news.caption.isEmpty {
							Text(news.caption)
								.font(.body)
								.padding(.top, 4)
						}
					}
					.frame(maxWidth: .infinity, alignment: .leading)
					
					VStack(spacing: 10) {
						if let app {
							Button {
								onOpenApp()
							} label: {
								Label(app.currentName, systemImage: "arrow.down.app")
									.frame(maxWidth: .infinity)
							}
							.buttonStyle(.borderedProminent)
						}
						
						if let url = news.url {
							Button {
								UIApplication.shared.open(url)
							} label: {
								Label(.localized("Open Link"), systemImage: "safari")
									.frame(maxWidth: .infinity)
							}
							.buttonStyle(.bordered)
						}
					}
					.controlSize(.large)
				}
				.padding()
			}
			.toolbar {
				ToolbarItem(placement: .topBarTrailing) {
					Button(.localized("Close")) { dismiss() }
				}
			}
		}
		.presentationDetents([.medium, .large])
	}
	
	@ViewBuilder
	private var _header: some View {
		ZStack(alignment: .bottomLeading) {
			(news.tintColor ?? Color.secondary).opacity(0.3)
			
			if let imageURL = news.imageURL {
				LazyImage(url: imageURL) { state in
					if let image = state.image {
						image
							.resizable()
							.aspectRatio(contentMode: .fill)
					}
				}
			}
		}
		.frame(height: 200)
		.frame(maxWidth: .infinity)
		.clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
		.overlay(
			RoundedRectangle(cornerRadius: 16, style: .continuous)
				.strokeBorder(Color.gray.opacity(0.2), lineWidth: 1)
		)
	}
}
