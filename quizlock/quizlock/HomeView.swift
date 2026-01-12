import SwiftUI

struct HomeView: View {
    @EnvironmentObject var model: AppModel
    @State private var showQuiz = false
    @State private var showGroupSelectionAlert = false
    @State private var showGroupSelection = false
    @State private var showQuestionList = false
    @State private var showNoAppsAlert = false
    @State private var showUnlockedAlert = false
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    statusCard
                    
                    VStack(spacing: 16) {
                        HStack(spacing: 12) {
                            Button {
                                showSettings = true
                            } label: {
                                VStack(spacing: 10) {
                                    Image(systemName: "gearshape.fill")
                                        .font(.title2)
                                        .foregroundStyle(.blue)
                                    Text("設定")
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 24)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                            }
                            
                            NavigationLink {
                                QuestionListView()
                            } label: {
                                VStack(spacing: 10) {
                                    Image(systemName: "list.bullet")
                                        .font(.title2)
                                        .foregroundStyle(.blue)
                                    Text("問題管理")
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 24)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                            }
                        }
                        
                        Button {
                            let result = model.startQuiz()
                            switch result {
                            case .success:
                                showQuiz = true
                            case .noGroupSelected, .noQuestions:
                                showGroupSelectionAlert = true
                            case .noAppsSelected:
                                showNoAppsAlert = true
                            case .unlocked:
                                showUnlockedAlert = true
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "play.circle.fill")
                                Text("クイズ開始")
                            }
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .shadow(color: Color.blue.opacity(0.3), radius: 4, x: 0, y: 2)
                        }
                    }
                }
                .padding()
            }
            .background(Color(white: 0.98))
            .navigationTitle("ホーム")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(isPresented: $showQuiz) {
                QuizView()
            }
            .onChange(of: model.shouldDismissQuiz) { oldValue, newValue in
                if newValue {
                    showQuiz = false
                    // フラグをリセット
                    model.shouldDismissQuiz = false
                }
            }
            .navigationDestination(isPresented: $showQuestionList) {
                QuestionListView()
            }
            .navigationDestination(isPresented: $showSettings) {
                SettingsView()
            }
            .alert("グループを選択してください", isPresented: $showGroupSelectionAlert) {
                Button("問題管理へ", role: .none) {
                    showQuestionList = true
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("クイズを開始するには、問題管理画面でグループを選択してください。")
            }
            .alert("制限するアプリが設定されていません", isPresented: $showNoAppsAlert) {
                Button("設定へ", role: .none) {
                    showSettings = true
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("クイズを開始するには、設定画面で制限するアプリを選択してください。")
            }
            .alert("解除中です", isPresented: $showUnlockedAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                if let until = model.unlockUntil {
                    Text("現在解除中です（\(until.formatted(date: .omitted, time: .shortened))まで）。解除期間が終了してからクイズを開始できます。")
                } else {
                    Text("現在解除中です。解除期間が終了してからクイズを開始できます。")
                }
            }
            .onAppear {
                // Screen Time権限状態を同期
                // syncBlocking()はquizlockAppのscenePhase.activeでstartRestrictionSync()が呼ばれるため不要
                model.syncScreenTimeAuthStatus()
            }
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Circle()
                    .fill(model.isBlockingNow ? Color.red : Color.green)
                    .frame(width: 12, height: 12)
                Text(model.isBlockingNow ? "ロック中" : "解除中")
                    .font(.headline)
                    .foregroundStyle(.primary)
            }

            Divider()
                .background(Color.gray.opacity(0.2))

            if let until = model.unlockUntil, Date() < until {
                HStack(spacing: 8) {
                    Image(systemName: "clock.fill")
                        .font(.caption)
                        .foregroundStyle(.blue)
                    Text("一時解除: \(until.formatted(date: .omitted, time: .shortened)) まで")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                    Text("通常状態")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}
