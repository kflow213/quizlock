import SwiftUI
import FamilyControls

struct DowntimeSettingsView: View {
    @EnvironmentObject var model: AppModel
    
    @State private var downtimeStart: Int = 19 * 60
    @State private var downtimeEnd: Int = 22 * 60
    @State private var downtimeWeekdays: Set<Weekday> = Set(Weekday.allCases)
    @State private var message: String?
    
    var body: some View {
        Form {
            // =========================
            // 時間設定
            // =========================
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("開始時刻")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        TimePicker(minutes: $downtimeStart)
                    }
                    
                    HStack {
                        Text("終了時刻")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        TimePicker(minutes: $downtimeEnd)
                    }
                }
                .padding(.vertical, 8)
            } header: {
                Text("時間設定")
            } footer: {
                Text("指定した時間帯にアプリをブロックします。")
            }
            
            // =========================
            // 曜日選択（有料機能）
            // =========================
            Section {
                ZStack {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("適用する曜日")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                            ForEach(Weekday.allCases, id: \.self) { weekday in
                                Button {
                                    if !model.isPro {
                                        return
                                    }
                                    if downtimeWeekdays.contains(weekday) {
                                        downtimeWeekdays.remove(weekday)
                                    } else {
                                        downtimeWeekdays.insert(weekday)
                                    }
                                } label: {
                                    Text(weekday.displayName)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .frame(width: 44, height: 44)
                                        .background(downtimeWeekdays.contains(weekday) ? Color.gray : Color.gray.opacity(0.2))
                                        .foregroundStyle(downtimeWeekdays.contains(weekday) ? .white : .gray)
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .disabled(!model.isPro)
                            }
                        }
                    }
                    .padding(.vertical, 8)
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
                            Text("曜日を自由に選択できます")
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
                Text("適用する曜日")
            } footer: {
                Text(model.isPro ? "選択した曜日のみ制限が適用されます" : "有料版では曜日を選択できます。無料版は全曜日のみ使用可能です。")
            }
            
            // =========================
            // アプリ選択
            // =========================
            Section {
                if model.screenTimeAuthStatus == .approved {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("休止時間で制限するアプリ")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)
                        FamilyActivityPicker(selection: Binding(
                            get: { model.downtimeActivitySelection },
                            set: { 
                                model.downtimeActivitySelection = $0
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
                Text("休止時間中にブロックするアプリを選択します。")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(white: 0.98))
        .navigationTitle("休止時間")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    if downtimeStart != downtimeEnd {
                        let ok = model.updateDowntime(
                            start: downtimeStart,
                            end: downtimeEnd,
                            weekdays: downtimeWeekdays
                        )
                        if ok {
                            message = "保存しました"
                            // メッセージを2秒後に消す
                            Task {
                                try? await Task.sleep(nanoseconds: 2_000_000_000)
                                message = nil
                            }
                        } else {
                            message = "開始と終了が同じ時刻は設定できません"
                        }
                    } else {
                        message = "開始と終了が同じ時刻は設定できません"
                    }
                } label: {
                    Image(systemName: "checkmark")
                        .font(.headline)
                        .foregroundStyle(.blue)
                }
            }
        }
        .onAppear {
            downtimeStart = model.slot.downtime.startMinutes
            downtimeEnd = model.slot.downtime.endMinutes
            downtimeWeekdays = model.slot.downtime.enabledWeekdays
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
            FamilyActivityPicker(selection: $model.downtimeActivitySelection)
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
