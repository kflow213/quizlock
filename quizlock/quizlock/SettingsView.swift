import SwiftUI
import FamilyControls
import UIKit
import StoreKit

struct SettingsView: View {
    @EnvironmentObject var model: AppModel

    @State private var showPurchaseView = false

    var body: some View {
        Form {
            // =========================
            // 休止時間（別ページに遷移）
            // =========================
            Section {
                NavigationLink {
                    DowntimeSettingsView()
                } label: {
                    HStack {
                        Image(systemName: "moon.fill")
                            .foregroundStyle(.blue)
                        Text("休止時間")
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.gray)
                    }
                }
            } header: {
                Text("休止時間")
            } footer: {
                Text("指定した時間帯と曜日にアプリをブロックします。")
            }
            
            // =========================
            // 使用時間制限（別ページに遷移）
            // =========================
            Section {
                NavigationLink {
                    AppLimitSettingsView()
                } label: {
                    HStack {
                        Image(systemName: "clock.fill")
                            .foregroundStyle(model.isPro ? .orange : .gray)
                        Text("使用時間制限")
                            .foregroundStyle(.primary)
                        if !model.isPro {
                            Spacer()
                            Text("有料機能")
                                .font(.caption)
                                .foregroundStyle(.gray)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.gray)
                    }
                }
            } header: {
                Text("使用時間制限")
            } footer: {
                Text(model.isPro ? "1日の使用時間を制限できます。" : "1日の使用時間を制限できます（有料機能）")
            }
            
            // =========================
            // 解除条件（別ページに遷移）
            // =========================
            Section {
                NavigationLink {
                    UnlockConditionSettingsView()
                } label: {
                    HStack {
                        Image(systemName: "lock.open.fill")
                            .foregroundStyle(.green)
                        Text("解除条件")
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.gray)
                    }
                }
            } header: {
                Text("解除条件")
            } footer: {
                Text("正解したときの解除方法を設定します。")
            }
            
        }
        .scrollContentBackground(.hidden)
        .background(Color(white: 0.98))
        .navigationTitle("設定")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showPurchaseView = true
                } label: {
                    if model.isPro {
                        Text("Pro")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.orange)
                    } else {
                        Text("Free")
                            .font(.subheadline)
                            .foregroundStyle(.blue)
                    }
                }
            }
        }
        .navigationDestination(isPresented: $showPurchaseView) {
            PurchaseView()
        }
        .onAppear {
            model.syncScreenTimeAuthStatus()
        }
    }

}
