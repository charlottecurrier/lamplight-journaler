import SwiftUI
import UIKit

/// A file ready to share.
struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

/// The system share sheet, for a file.
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
