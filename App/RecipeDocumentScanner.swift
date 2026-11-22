#if os(iOS)
import SwiftUI
import VisionKit

struct RecipeDocumentScanner: UIViewControllerRepresentable {
  var onScan: ([Data]) -> Void
  var onCancel: () -> Void

  static var isSupported: Bool {
    VNDocumentCameraViewController.isSupported
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(onScan: onScan, onCancel: onCancel)
  }

  func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
    let controller = VNDocumentCameraViewController()
    controller.delegate = context.coordinator
    return controller
  }

  func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) { }

  final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
    var onScan: ([Data]) -> Void
    var onCancel: () -> Void

    init(onScan: @escaping ([Data]) -> Void, onCancel: @escaping () -> Void) {
      self.onScan = onScan
      self.onCancel = onCancel
    }

    func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
      let pages = (0..<scan.pageCount).compactMap { scan.imageOfPage(at: $0).jpegData(compressionQuality: 0.86) }
      onScan(pages)
    }

    func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
      onCancel()
    }

    func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
      onCancel()
    }
  }
}
#endif
