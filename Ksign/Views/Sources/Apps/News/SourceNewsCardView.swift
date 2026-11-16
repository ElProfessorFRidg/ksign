//
//  SourceNewsCardView.swift
//  Feather
//

import SwiftUI
import AltSourceKit
import Nuke
import NukeUI

struct SourceNewsCardView: View {
    var new: ASRepository.News
    @State private var selectedImageIndex = 0

    private var imageURLs: [URL] { new.allImageURLs }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if imageURLs.count == 1, let url = imageURLs.first {
                image(url)
            } else if imageURLs.count > 1 {
                TabView(selection: $selectedImageIndex) {
                    ForEach(imageURLs.indices, id: \.self) { index in
                        Group {
                            if abs(index - selectedImageIndex) <= 1 {
                                image(imageURLs[index])
                            } else {
                                Color.gray.opacity(0.2)
                            }
                        }
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .frame(width: 250, height: 150)
            } else {
                Color.gray.opacity(0.2)
            }

            LinearGradient(
                colors: [.black.opacity(0.8), .clear],
                startPoint: .bottom,
                endPoint: .top
            )
            .frame(height: 100)
            .allowsHitTesting(false)

            Text(new.title)
                .font(.headline)
                .foregroundColor(.white)
                .lineLimit(2)
                .padding()
                .padding(.bottom, imageURLs.count > 1 ? 18 : 0)
                .allowsHitTesting(false)
        }
        .frame(width: 250, height: 150)
        .background(new.tintColor ?? Color.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if imageURLs.count > 1 {
                Text(verbatim: "\(selectedImageIndex + 1)/\(imageURLs.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.gray.opacity(0.2), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .onChange(of: imageURLs.count) { count in
            selectedImageIndex = min(selectedImageIndex, max(0, count - 1))
        }
    }

    private func image(_ url: URL) -> some View {
        LazyImage(url: url) { state in
            if let image = state.image {
                image.resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 250, height: 150)
            } else {
                Color.gray.opacity(0.2)
            }
        }
        .processors([ImageProcessors.Resize(size: CGSize(width: 500, height: 300))])
        .frame(width: 250, height: 150)
    }
}

