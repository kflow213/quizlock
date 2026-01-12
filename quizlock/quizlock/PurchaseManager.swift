import Foundation
import SwiftUI
import Combine
import StoreKit

@MainActor
class PurchaseManager: ObservableObject {
    static let shared = PurchaseManager()
    
    @Published var isPro: Bool = false
    @Published var isLoading: Bool = false
    @Published var currentSubscriptionProductId: String? = nil  // 現在のサブスクリプションID
    
    private let monthlyProductId = "com.quizlock.pro.monthly"
    private let yearlyProductId = "com.quizlock.pro.yearly"
    private let isProKey = "isPro"
    
    private init() {
        // UserDefaultsから課金状態を読み込み
        isPro = UserDefaults.standard.bool(forKey: isProKey)
        Task {
            await checkPurchaseStatus()
        }
        
        // Transaction.updatesをリッスン（成功した購入を見逃さないため）
        Task {
            await listenForTransactionUpdates()
        }
    }
    
    /// トランザクション更新をリッスン（アプリ起動時に呼び出される）
    /// - Note: アプリがバックグラウンドにいる間や、アプリが開いていない間に発生した購入も処理
    private func listenForTransactionUpdates() async {
        for await update in Transaction.updates {
            switch update {
            case .verified(let transaction):
                #if DEBUG
                print("[PurchaseManager] Transaction update received: \(transaction.productID)")
                #endif
                
                // Pro機能の商品IDかチェック
                if transaction.productID == monthlyProductId || transaction.productID == yearlyProductId {
                    await MainActor.run {
                        isPro = true
                        currentSubscriptionProductId = transaction.productID
                        UserDefaults.standard.set(true, forKey: isProKey)
                        #if DEBUG
                        print("[PurchaseManager] Pro status updated to true from transaction update")
                        #endif
                    }
                }
                
                // トランザクションを完了
                await transaction.finish()
                
            case .unverified(_, let error):
                #if DEBUG
                print("[PurchaseManager] Unverified transaction update: \(error)")
                #endif
            }
        }
    }
    
    /// 購入状態を確認
    func checkPurchaseStatus() async {
        isLoading = true
        defer { isLoading = false }
        
        #if DEBUG
        print("購入状態を確認中...")
        #endif
        // verified entitlementsを優先して確認
        var foundVerified = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                #if DEBUG
                print("検証済みトランザクション発見: \(transaction.productID)")
                #endif
                if transaction.productID == monthlyProductId || transaction.productID == yearlyProductId {
                    #if DEBUG
                    print("有効な購入が見つかりました: \(transaction.productID)")
                    #endif
                    isPro = true
                    currentSubscriptionProductId = transaction.productID
                    UserDefaults.standard.set(true, forKey: isProKey)
                    foundVerified = true
                    return
                }
            } else {
                #if DEBUG
                print("未検証のトランザクション: \(result)")
                #endif
            }
        }
        
        // verified entitlementsが見つからない場合はfalseに設定
        if !foundVerified {
            #if DEBUG
            print("有効な購入が見つかりませんでした")
            #endif
            isPro = false
            currentSubscriptionProductId = nil
            UserDefaults.standard.set(false, forKey: isProKey)
        }
    }
    
    /// 購入を開始
    func purchase(productId: String) async -> Bool {
        isLoading = true
        defer { isLoading = false }
        
        do {
            #if DEBUG
            print("購入開始: \(productId)")
            #endif
            // 製品情報を取得
            let products = try await Product.products(for: [productId])
            guard let product = products.first else {
                #if DEBUG
                print("エラー: 製品が見つかりません: \(productId)")
                print("StoreKit設定ファイル（Products.storekit）にこの商品IDが登録されているか確認してください。")
                #endif
                return false
            }
            
            #if DEBUG
            print("製品情報取得成功: \(product.displayName) - \(product.displayPrice)")
            #endif
            
            // 購入を実行
            let result = try await product.purchase()
            
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    // 購入成功
                    #if DEBUG
                    print("購入成功: \(transaction.productID)")
                    #endif
                    await transaction.finish()
                    isPro = true
                    UserDefaults.standard.set(true, forKey: isProKey)
                    await checkPurchaseStatus() // 状態を再確認
                    return true
                case .unverified:
                    #if DEBUG
                    print("エラー: トランザクションの検証に失敗しました")
                    #endif
                    return false
                }
            case .userCancelled:
                #if DEBUG
                print("ユーザーがキャンセルしました")
                #endif
                return false
            case .pending:
                #if DEBUG
                print("購入が保留中です")
                #endif
                return false
            @unknown default:
                #if DEBUG
                print("不明な購入結果")
                #endif
                return false
            }
        } catch {
            #if DEBUG
            print("購入エラー: \(error.localizedDescription)")
            print("エラー詳細: \(error)")
            #endif
            return false
        }
    }
    
    /// 利用可能な商品を取得
    func loadProducts() async -> [Product] {
        do {
            let productIds = [monthlyProductId, yearlyProductId]
            #if DEBUG
            print("商品IDを取得中: \(productIds)")
            #endif
            let products = try await Product.products(for: productIds)
            #if DEBUG
            print("取得した商品数: \(products.count)")
            for product in products {
                print("商品: \(product.id) - \(product.displayName) - \(product.displayPrice)")
            }
            if products.isEmpty {
                print("警告: 商品が取得できませんでした。StoreKit設定ファイル（Products.storekit）がXcodeプロジェクトに追加され、スキームで選択されているか確認してください。")
            }
            #endif
            return products
        } catch {
            #if DEBUG
            print("商品の取得に失敗しました: \(error.localizedDescription)")
            print("エラー詳細: \(error)")
            #endif
            return []
        }
    }
    
    /// 購入を復元
    func restorePurchases() async -> Bool {
        isLoading = true
        defer { isLoading = false }
        
        do {
            try await AppStore.sync()
            await checkPurchaseStatus()
            return isPro
        } catch {
            #if DEBUG
            print("復元エラー: \(error)")
            #endif
            return false
        }
    }
}
