import SwiftUI
import StoreKit

struct PurchaseView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var purchaseManager = PurchaseManager.shared
    @State private var purchaseMessage: String?
    @State private var isPurchasing = false
    @State private var products: [Product] = []
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // ヘッダー
                VStack(spacing: 12) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.gray)
                    
                    Text("Quiz Lock Pro")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(.gray)
                    
                    Text("すべての機能を利用できます")
                        .font(.subheadline)
                        .foregroundStyle(.gray.opacity(0.7))
                }
                .padding(.top, 40)
                
                // 機能リスト
                VStack(alignment: .leading, spacing: 16) {
                    FeatureRow(icon: "calendar", title: "曜日選択", description: "適用する曜日を自由に選択")
                    FeatureRow(icon: "clock", title: "使用時間制限", description: "1日の使用時間を制限")
                    FeatureRow(icon: "number", title: "必要正解数", description: "最大100問まで設定可能")
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                
                // 購入ボタン
                if purchaseManager.isPro {
                    VStack(spacing: 16) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text("有料版を利用中")
                        }
                        .font(.headline)
                        .foregroundStyle(.gray)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.gray.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        
                        // 現在のプラン表示と切り替え
                        if let currentProductId = purchaseManager.currentSubscriptionProductId {
                            Text("現在のプラン: \(currentProductId.contains("yearly") ? "年額プラン" : "月額プラン")")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            
                            Text("プランを変更するには、下のボタンから異なるプランを選択してください")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                    }
                }
                
                // 商品リスト（無課金ユーザーとProユーザー両方に表示）
                VStack(spacing: 12) {
                        if products.isEmpty && purchaseManager.isLoading {
                            HStack {
                                ProgressView()
                                Text("商品を読み込み中...")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                        } else if products.isEmpty {
                            // 商品が読み込めない場合のフォールバック
                            VStack(spacing: 12) {
                                Button {
                                    Task {
                                        isPurchasing = true
                                        let success = await purchaseManager.purchase(productId: "com.quizlock.pro.monthly")
                                        isPurchasing = false
                                        if success {
                                            purchaseMessage = "購入が完了しました"
                                            model.isPro = true
                                        } else {
                                            purchaseMessage = "購入に失敗しました"
                                        }
                                    }
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Quiz Lock Pro 月額")
                                                .font(.headline)
                                                .foregroundStyle(.white)
                                            Text("月間プラン")
                                                .font(.caption)
                                                .foregroundStyle(.white.opacity(0.8))
                                        }
                                        Spacer()
                                        Text("¥300")
                                            .font(.headline)
                                            .foregroundStyle(.white)
                                    }
                                    .padding()
                                    .background(Color.blue)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                                .disabled(isPurchasing || purchaseManager.isLoading)
                                
                                Button {
                                    Task {
                                        isPurchasing = true
                                        let success = await purchaseManager.purchase(productId: "com.quizlock.pro.yearly")
                                        isPurchasing = false
                                        if success {
                                            purchaseMessage = "購入が完了しました"
                                            model.isPro = true
                                        } else {
                                            purchaseMessage = "購入に失敗しました"
                                        }
                                    }
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Quiz Lock Pro 年額")
                                                .font(.headline)
                                                .foregroundStyle(.white)
                                            Text("年間プラン（お得）")
                                                .font(.caption)
                                                .foregroundStyle(.white.opacity(0.8))
                                        }
                                        Spacer()
                                        Text("¥3,000")
                                            .font(.headline)
                                            .foregroundStyle(.white)
                                    }
                                    .padding()
                                    .background(Color.orange)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                                .disabled(isPurchasing || purchaseManager.isLoading)
                            }
                        } else {
                            ForEach(products, id: \.id) { product in
                                let isCurrentPlan = purchaseManager.currentSubscriptionProductId == product.id
                                let isDifferentPlan = purchaseManager.isPro && purchaseManager.currentSubscriptionProductId != nil && purchaseManager.currentSubscriptionProductId != product.id
                                
                                Button {
                                    Task {
                                        isPurchasing = true
                                        let success = await purchaseManager.purchase(productId: product.id)
                                        isPurchasing = false
                                        if success {
                                            if isDifferentPlan {
                                                purchaseMessage = "プランを変更しました"
                                            } else {
                                                purchaseMessage = "購入が完了しました"
                                            }
                                            model.isPro = true
                                        } else {
                                            purchaseMessage = isDifferentPlan ? "プランの変更に失敗しました" : "購入に失敗しました"
                                        }
                                    }
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack(spacing: 8) {
                                                Text(product.displayName)
                                                    .font(.headline)
                                                    .foregroundStyle(.white)
                                                if isCurrentPlan {
                                                    Text("(現在)")
                                                        .font(.caption)
                                                        .foregroundStyle(.white.opacity(0.8))
                                                } else if isDifferentPlan {
                                                    Text("(変更)")
                                                        .font(.caption)
                                                        .foregroundStyle(.white.opacity(0.8))
                                                }
                                            }
                                            Text(product.id.contains("yearly") ? "年間プラン（お得）" : "月間プラン")
                                                .font(.caption)
                                                .foregroundStyle(.white.opacity(0.8))
                                        }
                                        Spacer()
                                        Text(product.displayPrice)
                                            .font(.headline)
                                            .foregroundStyle(.white)
                                    }
                                    .padding()
                                    .background(isCurrentPlan ? Color.gray : (product.id.contains("yearly") ? Color.orange : Color.blue))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                                .disabled((isPurchasing || purchaseManager.isLoading) && !isDifferentPlan)
                            }
                        }
                        
                        Button {
                            Task {
                                isPurchasing = true
                                let success = await purchaseManager.restorePurchases()
                                isPurchasing = false
                                if success {
                                    purchaseMessage = "購入を復元しました"
                                    model.isPro = true
                                } else {
                                    purchaseMessage = "復元する購入が見つかりませんでした"
                                }
                            }
                        } label: {
                            Text("購入を復元")
                                .font(.subheadline)
                                .foregroundStyle(.blue)
                        }
                        .disabled(isPurchasing || purchaseManager.isLoading)
                    }
                
                if let message = purchaseMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.gray)
                        .padding()
                }
                
                // 注意書き
                Text("購入はApp Storeアカウントに課金されます。\nサブスクリプションは自動更新されます。")
                    .font(.caption)
                    .foregroundStyle(.gray.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.top, 20)
            }
            .padding()
        }
        .background(Color(white: 0.95))
        .navigationTitle("アップグレード")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            products = await purchaseManager.loadProducts()
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.gray)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.gray)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.gray.opacity(0.7))
            }
            
            Spacer()
        }
    }
}
