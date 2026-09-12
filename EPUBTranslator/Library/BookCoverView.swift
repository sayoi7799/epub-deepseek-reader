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
                .fill(placeholderGradient)

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                VStack(spacing: 8) {
                    Text(book.title)
                        .font(.system(size: max(11, width * 0.12), weight: .semibold, design: .serif))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                        .padding(.horizontal, 10)
                    Text(book.authorDisplay)
                        .font(.system(size: max(9, width * 0.09)))
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                }
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.16), radius: 6, x: 0, y: 3)
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

    private var placeholderGradient: LinearGradient {
        let seed = abs(book.title.hashValue)
        let hue = Double(seed % 360) / 360
        return LinearGradient(
            colors: [
                Color(hue: hue, saturation: 0.42, brightness: 0.58),
                Color(hue: (hue + 0.08).truncatingRemainder(dividingBy: 1), saturation: 0.48, brightness: 0.38),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
