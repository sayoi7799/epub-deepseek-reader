import SwiftUI
import UIKit

struct BookCoverView: View {
    let book: Book
    let imageURL: URL?
    var width: CGFloat = 132

    @State private var image: UIImage?

    private var height: CGFloat { width * 1.5 }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(paperGradient)

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                placeholderCover
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.black.opacity(0.10), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 3)
        .task(id: imageURL) {
            guard let imageURL = self.imageURL else {
                image = nil
                return
            }
            let loaded = await Task.detached(priority: .utility) { () -> UIImage? in
                guard let data = try? Data(contentsOf: imageURL) else { return nil }
                return UIImage(data: data)
            }.value
            image = loaded
        }
    }

    /// 没有真实封面图时，画一个像样的"书"：左侧书脊 + 纸质底 + 书名 + 分隔线 + 作者。
    private var placeholderCover: some View {
        ZStack(alignment: .leading) {
            LinearGradient(
                colors: [Color(hex: "#F5EDDD"), Color(hex: "#E7D8BB")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Rectangle()
                .fill(spineGradient)
                .frame(width: width * 0.105)

            Rectangle()
                .fill(Color.black.opacity(0.06))
                .frame(width: width * 0.012)
                .offset(x: width * 0.105)

            VStack(spacing: width * 0.045) {
                Spacer(minLength: width * 0.12)

                Text(book.title)
                    .font(.system(size: max(11, width * 0.115), weight: .semibold, design: .serif))
                    .foregroundStyle(ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)

                Rectangle()
                    .fill(ink.opacity(0.28))
                    .frame(width: width * 0.2, height: 1)

                Text(book.authorDisplay)
                    .font(.system(size: max(8, width * 0.075), weight: .medium, design: .serif))
                    .foregroundStyle(ink.opacity(0.66))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                Spacer(minLength: width * 0.12)
            }
            .padding(.leading, width * 0.105 + width * 0.12)
            .padding(.trailing, width * 0.12)
            .frame(maxWidth: .infinity)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(ink.opacity(0.12), lineWidth: 0.8)
                .padding(width * 0.045)
        )
    }

    private var ink: Color {
        Color(hex: "#2C2721")
    }

    private var paperGradient: LinearGradient {
        return LinearGradient(
            colors: [Color(hex: "#F5EDDD"), Color(hex: "#E7D8BB")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// 书脊配色：用书名算出稳定的种子，从一组克制的颜色里挑一个。
    private var spineGradient: LinearGradient {
        let palette: [(String, String)] = [
            ("#3552B4", "#243A86"),
            ("#C08A3E", "#8F6326"),
            ("#B4636F", "#86424C"),
            ("#3E7C74", "#2A5A54"),
            ("#5A6480", "#3D455C"),
            ("#7A5A8C", "#563C65"),
        ]
        let seed = book.title.unicodeScalars.reduce(0) { partial, scalar in
            (partial &* 31 &+ Int(scalar.value)) & 0x7fffffff
        }
        let pair = palette[seed % palette.count]
        return LinearGradient(
            colors: [Color(hex: pair.0), Color(hex: pair.1)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
