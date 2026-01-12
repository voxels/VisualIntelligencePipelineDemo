import SwiftUI

struct FullScreenImageView: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            GeometryReader { proxy in
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .ignoresSafeArea()
            
            // Interaction overlay
            VStack {
                 HStack {
                     Button {
                         dismiss()
                     } label: {
                         Image(systemName: "xmark.circle.fill")
                             .font(.largeTitle)
                             .foregroundStyle(.white)
                             .padding()
                             .shadow(radius: 5)
                     }
                     Spacer()
                 }
                 Spacer()
            }
        }
    }
}
