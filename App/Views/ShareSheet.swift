import SwiftUI
import UIKit

/// A file ready to share.
struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

/// The system share sheet, for a file. `onFinish` is called when the person is done, whichever way.
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    var onFinish: () -> Void = {}

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in onFinish() }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
