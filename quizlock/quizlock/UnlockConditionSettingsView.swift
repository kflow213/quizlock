import SwiftUI

struct UnlockConditionSettingsView: View {
    @EnvironmentObject var model: AppModel
    
    @State private var unlockConditionType: UnlockConditionType = .immediate
    @State private var unlockDurationMinutes: Int = 10
    @State private var unlockRequiredQuestions: Int = 1
    @State private var isSkipEnabled: Bool = false
    @State private var message: String?
    
    var body: some View {
        Form {
            // =========================
            // 解除時間
            // =========================
            Section {
                HStack {
                    Text("解除時間")
                    Spacer()
                    DurationPicker(totalMinutes: $unlockDurationMinutes)
                }
            } header: {
                Text("解除時間")
            } footer: {
                Text("正解すると指定時間だけ解除されます。")
            }
            
            // =========================
            // 問題数
            // =========================
            Section {
                HStack {
                    Text("必要正解数")
                    Spacer()
                    Picker("", selection: $unlockRequiredQuestions) {
                        let maxQuestions = model.isPro ? 100 : 10
                        ForEach(1...maxQuestions, id: \.self) { count in
                            Text("\(count)問").tag(count)
                        }
                    }
                    .pickerStyle(.menu)
                }
                
                if !model.isPro && unlockRequiredQuestions > 10 {
                    Text("10問以上は有料機能です")
                        .font(.caption)
                        .foregroundStyle(.gray)
                }
            } header: {
                Text("問題数")
            } footer: {
                Text("指定問題数正解すると解除されます。")
            }
            
            // =========================
            // スキップ機能
            // =========================
            Section {
                Toggle("スキップ機能", isOn: $isSkipEnabled)
            } header: {
                Text("スキップ機能")
            } footer: {
                Text("有効にすると、問題がわからないときに問題を解かずにスクリーンタイムを解除できます。無効の場合は表示されません。")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(white: 0.98))
        .navigationTitle("解除条件")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    var hasError = false
                    
                    let maxQuestions = model.isPro ? 100 : 10
                    if unlockRequiredQuestions > maxQuestions {
                        message = "無課金ユーザーは10問まで設定できます"
                        hasError = true
                    }
                    
                    if !hasError {
                        // 解除時間と問題数の両方を保存（どちらも必須）
                        model.updateUnlockCondition(
                            durationMinutes: unlockDurationMinutes,
                            requiredQuestions: unlockRequiredQuestions,
                            isSkipEnabled: isSkipEnabled
                        )
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
            }
        }
        .onAppear {
            // 新しいAPIから値を読み込む
            unlockDurationMinutes = model.slot.unlockDurationMinutes
            unlockRequiredQuestions = model.slot.unlockRequiredQuestions
            isSkipEnabled = model.slot.isSkipEnabled
            // 後方互換性のため、unlockConditionTypeも設定
            unlockConditionType = model.slot.unlockConditionType
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
}
