import SwiftUI
import FamilyControls

struct AppLimitSettingsView: View {
    @EnvironmentObject var model: AppModel
    
    @State private var appLimitMinutes: Int? = nil
    @State private var message: String?
    
    var body: some View {
        Form {
            Section {
                ZStack {
                    HStack {
                        Text("1日の使用時間")
                        Spacer()
                        DurationPicker(totalMinutes: Binding(
                            get: { appLimitMinutes ?? 60 },
                            set: { appLimitMinutes = $0 }
                        ), allowZero: false)
                    }
                    .opacity(model.isPro ? 1.0 : 0.3)
                    
                    // Proプラン説明ブロック（無課金ユーザーのみ表示）
                    if !model.isPro {
                        VStack(spacing: 12) {
                            Image(systemName: "crown.fill")
                                .font(.title)
                                .foregroundStyle(.orange)
                            Text("Proプランで利用可能")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text("1日の使用時間を制限できます")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            NavigationLink {
                                PurchaseView()
                            } label: {
                                Text("アップグレード")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color.orange)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color(uiColor: .systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                    }
                }
            } header: {
                Text("使用時間制限")
            } footer: {
                Text(model.isPro ? "1日の使用時間が制限に達すると、クイズに正解するまでブロックされます。" : "1日の使用時間を制限できます（有料機能）")
            }
            
            if model.isPro {
                
                // =========================
                // アプリ選択
                // =========================
                Section {
                    if model.screenTimeAuthStatus == .approved {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("使用時間制限で制限するアプリ")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)
                            FamilyActivityPicker(selection: Binding(
                                get: { model.appLimitActivitySelection },
                                set: { 
                                    model.appLimitActivitySelection = $0
                                    model.persistAll()
                                    // syncBlocking()内でrescheduleBoundarySync()が呼ばれるため、重複呼び出しを避ける
                                    model.syncBlocking()
                                }
                            ))
                            .frame(height: 280)
                        }
                    } else {
                        appPickerGate
                    }
                } header: {
                    Text("アプリ制限")
                } footer: {
                    Text("使用時間制限に達したときにブロックするアプリを選択します。")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(white: 0.98))
        .navigationTitle("使用時間制限")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    if model.isPro {
                        model.updateAppLimit(dailyLimitMinutes: appLimitMinutes)
                        message = "保存しました"
                        // メッセージを2秒後に消す
                        Task {
                            try? await Task.sleep(nanoseconds: 2_000_000_000)
                            message = nil
                        }
                    }
                } label: {
                    Image(systemName: "checkmark")
                        .font(.headline)
                        .foregroundStyle(.blue)
                }
                .disabled(!model.isPro)
            }
        }
        .onAppear {
            appLimitMinutes = model.slot.appLimit.dailyLimitMinutes ?? 0  // デフォルト0分
            model.syncScreenTimeAuthStatus()
        }
        .onDisappear {
            model.persistAll()
        }
        .overlay {
            if let message {
                VStack {
                    Spacer()
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(message.contains("保存しました") ? Color.green : Color.red)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .padding(.bottom, 100)
                }
            }
        }
    }
    
    @ViewBuilder
    private var appPickerGate: some View {
        switch model.screenTimeAuthStatus {
        case .approved:
            FamilyActivityPicker(selection: $model.appLimitActivitySelection)
                .frame(height: 320)
        case .notDetermined:
            Button {
                Task {
                    await model.requestScreenTimeAuthorizationFromUser()
                }
            } label: {
                Text("制限するアプリを選択")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.gray)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        case .denied:
            Button {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            } label: {
                Text("設定アプリで権限を許可")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.gray)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        @unknown default:
            Button {
                Task {
                    await model.requestScreenTimeAuthorizationFromUser()
                }
            } label: {
                Text("制限するアプリを選択")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.gray)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
    }
}
