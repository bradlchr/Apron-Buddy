import StoreKit
import SwiftUI

struct TipJarView: View {
  @KitchenPalette private var palette
  @State private var products: [Product] = []
  @State private var isLoading = true
  @State private var purchaseInProgress = false
  @State private var message: String?

  var body: some View {
    Form {
      Section {
        Text("Thank you for using Apron Buddy. An optional one-time tip helps support independent development. All features are available without tipping.")
          .foregroundStyle(.secondary)
      }
      .listRowBackground(palette.surface)

      Section {
        if isLoading {
          ProgressView("Loading tips…")
        } else if products.isEmpty {
          Text("The App Store couldn’t load tip options.").foregroundStyle(.secondary)
          Button("Try again") { Task { await loadProducts() } }
        }
        ForEach(products, id: \.id) { product in
          Button {
            Task { await purchase(product) }
          } label: {
            HStack {
              Label(product.displayName, systemImage: "heart")
              Spacer()
              Text(product.displayPrice).fontWeight(.semibold)
            }
          }
          .disabled(purchaseInProgress)
        }
        if let message {
          Text(message).foregroundStyle(.secondary)
        }
      }
      .listRowBackground(palette.surface)
    }
    .scrollContentBackground(.hidden)
    .background(palette.paper)
    .tint(palette.accent)
    .navigationTitle("Chef’s Tip Jar")
    .task { await loadProducts() }
  }

  private func loadProducts() async {
    isLoading = true
    defer { isLoading = false }
    products = (try? await Product.products(for: ChefTips.productIDs))?.sorted { $0.price < $1.price } ?? []
  }

  private func purchase(_ product: Product) async {
    guard !purchaseInProgress else { return }
    purchaseInProgress = true
    message = nil
    defer { purchaseInProgress = false }

    do {
      switch try await product.purchase() {
      case .success(let result):
        if await ChefTips.finish(result) {
          message = "Thank you for supporting Apron Buddy!"
        } else {
          message = "The App Store couldn’t verify the tip."
        }
      case .pending:
        message = "Your tip is awaiting App Store approval."
      case .userCancelled:
        break
      @unknown default:
        break
      }
    } catch {
      message = "The App Store couldn’t complete your tip. Please try again."
    }
  }
}

enum ChefTips {
  static let productIDs: Set<String> = [
    "apronbuddy.tip.small",
    "apronbuddy.tip.medium",
    "apronbuddy.tip.large"
  ]

  static func listen() async {
    async let backlog: Void = finishUnfinished()
    for await result in StoreKit.Transaction.updates {
      _ = await finish(result)
    }
    await backlog
  }

  private static func finishUnfinished() async {
    for await result in StoreKit.Transaction.unfinished {
      _ = await finish(result)
    }
  }

  static func finish(_ result: VerificationResult<StoreKit.Transaction>) async -> Bool {
    guard case .verified(let transaction) = result, productIDs.contains(transaction.productID) else { return false }
    await transaction.finish()
    return true
  }
}
