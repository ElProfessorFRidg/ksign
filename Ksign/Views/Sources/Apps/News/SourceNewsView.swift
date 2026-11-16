//
//  SourceNewsView.swift
//  Feather
//

import SwiftUI
import AltSourceKit

struct SourceNewsView: View {
    var news: [ASRepository.News]?
    var onSelect: ((ASRepository.News) -> Void)? = nil

    var body: some View {
        Group {
            if let news, !news.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        ForEach(newestFirstNews, id: \.id) { item in
                            SourceNewsCardView(new: item)
                                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .onTapGesture { onSelect?(item) }
                        }
                    }
                    .padding(.horizontal, 21)
                }
                .frame(height: 150)
            }
        }
        .frame(height: news?.isEmpty == false ? 150 : 0)
    }

    private var newestFirstNews: [ASRepository.News] {
        (news ?? []).enumerated().sorted { lhs, rhs in
            let lhsDate = lhs.element.date?.date ?? .distantPast
            let rhsDate = rhs.element.date?.date ?? .distantPast
            return lhsDate == rhsDate ? lhs.offset < rhs.offset : lhsDate > rhsDate
        }.map(\.element)
    }
}

