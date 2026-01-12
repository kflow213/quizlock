import Foundation
import SwiftUI
import Combine
import FamilyControls
import ManagedSettings
import DeviceActivity

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    // MARK: - Persisted
    @Published var pack: QuestionPack = .defaultPack
    @Published var slot: LockSlot = LockSlot()
    @Published var activitySelection: FamilyActivitySelection = FamilyActivitySelection()  // 全体のアプリ選択（旧仕様）
    @Published var downtimeActivitySelection: FamilyActivitySelection = FamilyActivitySelection()  // 休止時間用（課金機能）
    @Published var appLimitActivitySelection: FamilyActivitySelection = FamilyActivitySelection()  // 使用時間制限用（課金機能）

    // 初回説明フラグ（RootView / IntroView が参照）
    @Published var hasSeenIntro: Bool

    // MARK: - Quiz
    @Published var currentShuffled: ShuffledQuestion?
    @Published var lastAnswerWasCorrect: Bool? = nil
    @Published var correctCount: Int = 0  // 現在のセッションでの正解数

    // MARK: - Runtime
    @Published var isBlockingNow: Bool = false
    @Published var unlockUntil: Date? = nil
    @Published var isAppLimitReached: Bool = false  // App Limitが到達したかどうか
    @Published var shouldDismissQuiz: Bool = false  // クイズ画面を閉じるフラグ
    
    // 自動再ロックタイマー
    private var unlockTimerTask: Task<Void, Never>?
    
    // 制限同期用のタスク
    private var restrictionHeartbeatTask: Task<Void, Never>?  // フォアグラウンドでのハートビート
    private var boundarySyncTask: Task<Void, Never>?  // 境界時刻での同期
    private let heartbeatInterval: TimeInterval = 5.0  // 5秒ごとに同期

    // 課金状態（PurchaseManagerと同期）
    @Published var isPro: Bool = false {
        didSet {
            // Proステータスが変更された場合、ブロック状態と境界時刻を再評価
            if oldValue != isPro {
                setupAppLimitSchedule()
                // syncBlocking()内でrescheduleBoundarySync()が呼ばれるため、重複呼び出しを避ける
                syncBlocking()
            }
        }
    }
    private var purchaseManager: PurchaseManager { PurchaseManager.shared }
    
    @Published var screenTimeAuthStatus: AuthorizationStatus =
        AuthorizationCenter.shared.authorizationStatus
    
    // 表示用テキスト
    var screenTimeAuthStatusText: String {
        switch screenTimeAuthStatus {
        case .notDetermined:
            return "未確認"
        case .denied:
            return "拒否"
        case .approved:
            return "許可済み"
        @unknown default:
            return "不明"
        }
    }
    
    /// Screen Time 権限が承認済みか
    var isScreenTimeAuthorized: Bool {
        AuthorizationCenter.shared.authorizationStatus == .approved
    }


    private let store = ManagedSettingsStore()
    private static let hasSeenIntroKey = "hasSeenIntro_v1"
    
    // DeviceActivity用のスケジュール名
    private static let appLimitScheduleName = DeviceActivityName("appLimitSchedule")
    private static let downtimeScheduleName = DeviceActivityName("downtimeSchedule")
    private static let downtimeScheduleOvernightName = DeviceActivityName("downtimeScheduleOvernight")
    private static let unlockWindowName = DeviceActivityName("unlockWindow")

    private init() {
        // Publishedは初期値が必要
        self.hasSeenIntro = UserDefaults.standard.bool(forKey: Self.hasSeenIntroKey)
        
        // 課金状態を同期（完了後にスケジュールを設定）
        self.isPro = purchaseManager.isPro
        Task {
            await purchaseManager.checkPurchaseStatus()
            let newIsPro = purchaseManager.isPro
            // Proステータス確認後にスケジュールを設定（確実に動作させるため）
            await MainActor.run {
                isPro = newIsPro
                setupAppLimitSchedule()
                // Proステータスが変更された場合、ブロック状態を再評価
                // syncBlocking()内でrescheduleBoundarySync()が呼ばれるため、重複呼び出しを避ける
                syncBlocking()
            }
        }

        loadAll()
        // 初期状態でApp GroupからisAppLimitReachedを読み取る
        syncAppLimitReachedFromAppGroup()
        
        // Downtimeスケジュールを設定（起動時）
        setupDowntimeSchedule()
        
        // Unlockスケジュールを設定（起動時、unlockUntilが存在する場合）
        setupUnlockSchedule(unlockUntil: unlockUntil)
        
        syncBlocking()
        
        // 制限同期を開始（アプリ起動時）
        startRestrictionSync()
    }

    // MARK: - Intro
    func setSeenIntro() {
        hasSeenIntro = true
        UserDefaults.standard.set(true, forKey: Self.hasSeenIntroKey)
    }

    // MARK: - Persistence
    func persistAll() {
        // UserDefaults.standardに保存（既存の動作）
        AppStorageIO.save(pack: pack, slot: slot, selection: activitySelection, downtimeSelection: downtimeActivitySelection, appLimitSelection: appLimitActivitySelection, unlockUntil: unlockUntil)
        
        // App Groupにも保存（Extension用）
        SharedRestrictionState.save(
            lockSlot: slot,
            downtimeSelection: downtimeActivitySelection,
            appLimitSelection: appLimitActivitySelection,
            fallbackSelection: activitySelection,
            unlockUntil: unlockUntil,
            isPro: isPro
        )
    }

    func loadAll() {
        let loaded = AppStorageIO.load()
        pack = loaded.pack
        slot = loaded.slot
        activitySelection = loaded.selection
        downtimeActivitySelection = loaded.downtimeSelection
        appLimitActivitySelection = loaded.appLimitSelection
        unlockUntil = loaded.unlockUntil
    }

    // MARK: - Slot
    /// 休止時間設定を更新（完全に独立）
    /// - Parameters:
    ///   - start: 開始時刻（分単位、0-1439）
    ///   - end: 終了時刻（分単位、0-1439）
    ///   - weekdays: 適用する曜日
    /// - Returns: 更新成功時true、start==endの場合はfalse
    func updateDowntime(start: Int, end: Int, weekdays: Set<Weekday>) -> Bool {
        guard start != end else { return false }
        
        // 無課金ユーザーは全曜日のみ
        let finalWeekdays = isPro ? weekdays : Set(Weekday.allCases)
        
        slot.downtime.startMinutes = start
        slot.downtime.endMinutes = end
        slot.downtime.enabledWeekdays = finalWeekdays
        
        persistAll()
        // syncBlocking()内でrescheduleBoundarySync()が呼ばれるため、重複呼び出しを避ける
        syncBlocking()
        return true
    }
    
    /// 使用時間制限設定を更新（完全に独立）
    /// - Parameter dailyLimitMinutes: 1日の使用時間制限（分単位、nilの場合は無制限）
    func updateAppLimit(dailyLimitMinutes: Int?) {
        slot.appLimit.dailyLimitMinutes = dailyLimitMinutes
        persistAll()
        setupAppLimitSchedule()
        // syncBlocking()内でrescheduleBoundarySync()が呼ばれるため、重複呼び出しを避ける
        syncBlocking()
    }
    
    // 後方互換性のためのメソッド（既存コードとの互換性）
    func updateSlot(start: Int, end: Int) -> Bool {
        return updateDowntime(start: start, end: end, weekdays: slot.downtime.enabledWeekdays)
    }
    
    func updateRestrictionType(_ type: TimeRestrictionType) {
        // 分離された設定では使用しないが、後方互換性のため残す
        persistAll()
        syncBlocking()
    }
    
    func updateWeekdays(_ weekdays: Set<Weekday>) {
        slot.downtime.enabledWeekdays = isPro ? weekdays : Set(Weekday.allCases)
        persistAll()
        syncBlocking()
    }
    
    func updateDailyLimit(_ minutes: Int?) {
        // updateAppLimit内でsetupAppLimitSchedule()が呼ばれるため、ここでは呼ばない
        updateAppLimit(dailyLimitMinutes: minutes)
    }
    
    /// App Limit用のDeviceActivityスケジュールを設定
    /// - Note: 日次制限に達した場合、DeviceActivity Monitor ExtensionがApp GroupにisAppLimitReachedを書き込む
    ///          Proステータス確認後に呼び出されることを想定
    private func setupAppLimitSchedule() {
        guard isPro, let dailyLimit = slot.appLimit.dailyLimitMinutes, dailyLimit > 0 else {
            // スケジュールを削除（非Proユーザーまたは制限が無効な場合）
            try? DeviceActivityCenter().stopMonitoring([Self.appLimitScheduleName])
            // UserDefaultsにも保存（DeviceActivity Monitor Extension用）
            UserDefaults(suiteName: "group.com.kflow.quizlock")?.set(nil, forKey: "dailyLimitMinutes")
            // App GroupからisAppLimitReachedをクリア
            UserDefaults(suiteName: "group.com.kflow.quizlock")?.set(false, forKey: "isAppLimitReached")
            #if DEBUG
            print("[AppModel] App Limit schedule stopped (not Pro or no limit)")
            #endif
            return
        }
        
        #if DEBUG
        print("[AppModel] Setting up App Limit schedule: \(dailyLimit) minutes")
        #endif
        
        // UserDefaultsに保存（DeviceActivity Monitor Extension用）
        UserDefaults(suiteName: "group.com.kflow.quizlock")?.set(dailyLimit, forKey: "dailyLimitMinutes")
        
        // App Limit設定を更新
        slot.appLimit.dailyLimitMinutes = dailyLimit
        
        // 日次制限のスケジュールを設定
        // 注意: 実際の使用時間追跡はDeviceActivity Monitor Extensionで行う
        let startComponents = DateComponents(hour: 0, minute: 0)
        let endComponents = DateComponents(hour: 23, minute: 59)
        let schedule = DeviceActivitySchedule(
            intervalStart: startComponents,
            intervalEnd: endComponents,
            repeats: true
        )
        
        do {
            let center = DeviceActivityCenter()
            // スケジュールの監視を開始
            try center.startMonitoring(Self.appLimitScheduleName, during: schedule)
            
            // イベントを設定（使用時間が制限に達したら発火）
            // 注意: DeviceActivityEventの監視は、DeviceActivity Monitor Extensionで処理されます
            let eventName = DeviceActivityEvent.Name("appLimitEvent")
            let event = DeviceActivityEvent(
                applications: appLimitActivitySelection.applicationTokens,
                threshold: DateComponents(minute: dailyLimit)
            )
            // イベントの監視を開始（eventsパラメータは辞書形式）
            try center.startMonitoring(Self.appLimitScheduleName, during: schedule, events: [eventName: event])
            #if DEBUG
            print("[AppModel] App Limit schedule started successfully")
            #endif
        } catch {
            #if DEBUG
            print("[AppModel] DeviceActivity schedule setup failed: \(error)")
            #endif
            // エラーが発生してもアプリは動作を続ける
        }
    }
    
    /// Downtime用のDeviceActivityスケジュールを設定
    /// - Note: 日跨ぎの場合、2つのスケジュールを作成（[start, 23:59]と[00:00, end]）
    private func setupDowntimeSchedule() {
        let downtime = slot.downtime
        
        // 既存のスケジュールを停止
        let center = DeviceActivityCenter()
        try? center.stopMonitoring([Self.downtimeScheduleName, Self.downtimeScheduleOvernightName])
        
        // 有効な曜日がない場合はスケジュールを設定しない
        guard !downtime.enabledWeekdays.isEmpty else {
            #if DEBUG
            print("[AppModel] Downtime schedule stopped (no enabled weekdays)")
            #endif
            return
        }
        
        let startMinutes = downtime.startMinutes
        let endMinutes = downtime.endMinutes
        
        #if DEBUG
        print("[AppModel] Setting up Downtime schedule: \(startMinutes/60):\(startMinutes%60) - \(endMinutes/60):\(endMinutes%60)")
        #endif
        
        if startMinutes < endMinutes {
            // 同日枠：1つのスケジュール
            let startComponents = DateComponents(hour: startMinutes / 60, minute: startMinutes % 60)
            let endComponents = DateComponents(hour: endMinutes / 60, minute: endMinutes % 60)
            let schedule = DeviceActivitySchedule(
                intervalStart: startComponents,
                intervalEnd: endComponents,
                repeats: true
            )
            
            do {
                try center.startMonitoring(Self.downtimeScheduleName, during: schedule)
                #if DEBUG
                print("[AppModel] Downtime schedule started (same-day)")
                #endif
            } catch {
                #if DEBUG
                print("[AppModel] Downtime schedule setup failed: \(error)")
                #endif
            }
        } else if startMinutes > endMinutes {
            // 日跨ぎ枠：2つのスケジュール
            // 1. [start, 23:59]
            let startComponents1 = DateComponents(hour: startMinutes / 60, minute: startMinutes % 60)
            let endComponents1 = DateComponents(hour: 23, minute: 59)
            let schedule1 = DeviceActivitySchedule(
                intervalStart: startComponents1,
                intervalEnd: endComponents1,
                repeats: true
            )
            
            // 2. [00:00, end]
            let startComponents2 = DateComponents(hour: 0, minute: 0)
            let endComponents2 = DateComponents(hour: endMinutes / 60, minute: endMinutes % 60)
            let schedule2 = DeviceActivitySchedule(
                intervalStart: startComponents2,
                intervalEnd: endComponents2,
                repeats: true
            )
            
            do {
                try center.startMonitoring(Self.downtimeScheduleName, during: schedule1)
                try center.startMonitoring(Self.downtimeScheduleOvernightName, during: schedule2)
                #if DEBUG
                print("[AppModel] Downtime schedule started (overnight: 2 schedules)")
                #endif
            } catch {
                #if DEBUG
                print("[AppModel] Downtime schedule setup failed: \(error)")
                #endif
            }
        }
    }
    
    /// Unlock期限用のDeviceActivityスケジュールを設定
    /// - Parameter unlockUntil: 解除期限（nilの場合はスケジュールを停止）
    private func setupUnlockSchedule(unlockUntil: Date?) {
        let center = DeviceActivityCenter()
        
        // 既存のスケジュールを停止
        try? center.stopMonitoring([Self.unlockWindowName])
        
        guard let unlockUntil = unlockUntil, unlockUntil > Date() else {
            #if DEBUG
            print("[AppModel] Unlock schedule stopped (no valid unlockUntil)")
            #endif
            return
        }
        
        let now = Date()
        let cal = Calendar.current
        
        // 現在時刻からunlockUntilまでのスケジュール（非繰り返し）
        let startComponents = cal.dateComponents([.year, .month, .day, .hour, .minute], from: now)
        let endComponents = cal.dateComponents([.year, .month, .day, .hour, .minute], from: unlockUntil)
        
        let schedule = DeviceActivitySchedule(
            intervalStart: startComponents,
            intervalEnd: endComponents,
            repeats: false  // 1回のみ
        )
        
        do {
            try center.startMonitoring(Self.unlockWindowName, during: schedule)
            #if DEBUG
            print("[AppModel] Unlock schedule started: until \(unlockUntil)")
            #endif
        } catch {
            #if DEBUG
            print("[AppModel] Unlock schedule setup failed: \(error)")
            #endif
        }
    }

    // MARK: - Blocking
    /// App GroupからisAppLimitReachedを読み取る
    /// DeviceActivity Monitor Extensionは別プロセスで動作するため、App Group経由で状態を共有
    private func syncAppLimitReachedFromAppGroup() {
        if let sharedDefaults = UserDefaults(suiteName: "group.com.kflow.quizlock") {
            let reached = sharedDefaults.bool(forKey: "isAppLimitReached")
            if isAppLimitReached != reached {
                isAppLimitReached = reached
                #if DEBUG
                print("[AppModel] App Limit reached state synced from App Group: \(reached)")
                #endif
            }
        }
    }
    
    /// ブロック状態を同期（アプリ起動時・復帰時に呼ばれる）
    /// - Parameter now: 現在時刻（デフォルトはDate()）
    /// - Note: 一時解除中（unlockUntil）の場合はロックしない
    ///         解除期限が過ぎた場合、制限条件を再評価して再ブロックする
    ///         App GroupからisAppLimitReachedを読み取ってから判定する
    ///         アンロック期限後は、元の制限タイプ（Downtime/App Limit）に基づいて再ロック
    func syncBlocking(now: Date = Date()) {
        // App Groupから最新の状態を読み取る（DeviceActivity Monitor Extensionが別プロセスで更新）
        syncAppLimitReachedFromAppGroup()
        
        // 解除中ならロックしない
        if let until = unlockUntil, now < until {
            removeBlockingNow()
            return
        }
        
        // 解除期限が過ぎた場合の処理
        if let until = unlockUntil, now >= until {
        unlockUntil = nil
            unlockTimerTask?.cancel()
            unlockTimerTask = nil
            setupUnlockSchedule(unlockUntil: nil)  // Unlockスケジュールを停止
            persistAll()
            
            // アンロック期限後は、元の制限タイプに基づいて再ロック
            // Downtime: 現在時刻がダウンタイムウィンドウ内なら即座に再ロック
            // App Limit: 同じ日の23:59まで再ロック（標準的なScreen Time動作）
            let shouldBlockDowntime = shouldBlockForDowntime(now: now)
            let shouldBlockAppLimit = shouldBlockForAppLimit(now: now)
            
            if shouldBlockDowntime || shouldBlockAppLimit {
                applyBlockingNow(shouldBlockDowntime: shouldBlockDowntime, shouldBlockAppLimit: shouldBlockAppLimit)
            } else {
                removeBlockingNow()
            }
            return
        }

        // アンロック中でない場合、通常のブロック判定
        let shouldBlockDowntime = shouldBlockForDowntime(now: now)
        let shouldBlockAppLimit = shouldBlockForAppLimit(now: now)
        
        if shouldBlockDowntime || shouldBlockAppLimit {
            applyBlockingNow(shouldBlockDowntime: shouldBlockDowntime, shouldBlockAppLimit: shouldBlockAppLimit)
        } else {
            removeBlockingNow()
        }
        
        // 境界時刻のスケジュールを更新（syncBlocking後）
        rescheduleBoundarySync()
    }
    
    // MARK: - Restriction Sync Management
    
    /// 制限同期を開始（フォアグラウンドでのハートビートと境界時刻の監視）
    func startRestrictionSync() {
        #if DEBUG
        print("[AppModel] Starting restriction sync")
        #endif
        
        // 既存のタスクを停止
        stopRestrictionSync()
        
        // ハートビートを開始
        startRestrictionHeartbeat()
        
        // 境界時刻のスケジュールを設定
        rescheduleBoundarySync()
    }
    
    /// 制限同期を停止
    func stopRestrictionSync() {
        #if DEBUG
        print("[AppModel] Stopping restriction sync")
        #endif
        
        restrictionHeartbeatTask?.cancel()
        restrictionHeartbeatTask = nil
        
        boundarySyncTask?.cancel()
        boundarySyncTask = nil
    }
    
    /// フォアグラウンドでのハートビートを開始（定期的にsyncBlockingを呼び出す）
    private func startRestrictionHeartbeat() {
        restrictionHeartbeatTask?.cancel()
        
        restrictionHeartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: UInt64((self?.heartbeatInterval ?? 5.0) * 1_000_000_000))
                    
                    guard !Task.isCancelled else { break }
                    
                    await MainActor.run {
                        self?.syncAppLimitReachedFromAppGroup()
                        self?.syncBlocking()
                        #if DEBUG
                        print("[AppModel] Heartbeat sync completed")
                        #endif
                    }
                } catch {
                    // キャンセルされた場合は終了
                    break
                }
            }
        }
    }
    
    /// 境界時刻のスケジュールを再設定
    /// - Note: unlockUntil、Downtime開始/終了時刻、App Limitの日次リセット時刻を監視
    /// - Important: 無限再帰を防ぐため、常にTask.sleepでスケジュールし、同期的にsyncBlocking()を呼び出さない
    func rescheduleBoundarySync() {
        // 既存のタスクをキャンセル（新しいスケジュールを設定する前に）
        boundarySyncTask?.cancel()
        #if DEBUG
        print("[AppModel] rescheduleBoundarySync: cancelled existing task")
        #endif
        
        let now = Date()
        let cal = Calendar.current
        let epsilon: TimeInterval = 0.5  // 最小遅延時間（0.5秒）
        
        // すべての境界時刻を収集
        var boundaries: [Date] = []
        
        // 1. unlockUntil（存在する場合）
        if let until = unlockUntil, until > now {
            boundaries.append(until)
        }
        
        // 2. Downtime開始/終了時刻（今日と明日）
        let downtime = slot.downtime
        if !downtime.enabledWeekdays.isEmpty {
            let currentWeekday = Weekday(rawValue: cal.component(.weekday, from: now))
            
            if let weekday = currentWeekday, downtime.enabledWeekdays.contains(weekday) {
                // 今日のDowntime境界時刻を計算
                let startMinutes = downtime.startMinutes
                let endMinutes = downtime.endMinutes
                
                // 開始時刻
                if let startDate = cal.date(bySettingHour: startMinutes / 60, minute: startMinutes % 60, second: 0, of: now) {
                    if startDate > now {
                        boundaries.append(startDate)
                    } else if startMinutes > endMinutes {
                        // 日跨ぎの場合、明日の開始時刻
                        if let tomorrowStart = cal.date(byAdding: .day, value: 1, to: startDate) {
                            boundaries.append(tomorrowStart)
                        }
                    }
                }
                
                // 終了時刻
                if let endDate = cal.date(bySettingHour: endMinutes / 60, minute: endMinutes % 60, second: 0, of: now) {
                    if endDate > now {
                        boundaries.append(endDate)
                    } else if startMinutes > endMinutes {
                        // 日跨ぎの場合、明日の終了時刻
                        if let tomorrowEnd = cal.date(byAdding: .day, value: 1, to: endDate) {
                            boundaries.append(tomorrowEnd)
                        }
                    }
                }
            }
            
            // 明日のDowntime境界時刻も計算（今日が有効でない場合）
            if let tomorrow = cal.date(byAdding: .day, value: 1, to: now) {
                let tomorrowWeekday = Weekday(rawValue: cal.component(.weekday, from: tomorrow))
                if let weekday = tomorrowWeekday, downtime.enabledWeekdays.contains(weekday) {
                    let startMinutes = downtime.startMinutes
                    let endMinutes = downtime.endMinutes
                    
                    if let tomorrowStart = cal.date(bySettingHour: startMinutes / 60, minute: startMinutes % 60, second: 0, of: tomorrow) {
                        boundaries.append(tomorrowStart)
                    }
                    if let tomorrowEnd = cal.date(bySettingHour: endMinutes / 60, minute: endMinutes % 60, second: 0, of: tomorrow) {
                        boundaries.append(tomorrowEnd)
                    }
                }
            }
        }
        
        // 3. App Limitの日次リセット時刻（23:59）
        if isPro, slot.appLimit.dailyLimitMinutes != nil {
            if let endOfDay = cal.date(bySettingHour: 23, minute: 59, second: 0, of: now) {
                if endOfDay > now {
                    boundaries.append(endOfDay)
                } else {
                    // 今日が既に過ぎている場合、明日の23:59
                    if let tomorrowEndOfDay = cal.date(byAdding: .day, value: 1, to: endOfDay) {
                        boundaries.append(tomorrowEndOfDay)
                    }
                }
            }
        }
        
        // 境界時刻候補をフィルタリング：未来の時刻（イプシロン以上）のみを保持
        let futureBoundaries = boundaries.filter { boundary in
            let timeInterval = boundary.timeIntervalSince(now)
            return timeInterval > epsilon
        }
        
        // 最も近い境界時刻を取得
        guard let nextBoundary = futureBoundaries.min() else {
            #if DEBUG
            print("[AppModel] rescheduleBoundarySync: No future boundary times to schedule (filtered \(boundaries.count) candidates)")
            #endif
            return
        }
        
        let delay = nextBoundary.timeIntervalSince(now)
        // 安全な遅延時間を計算（最小イプシロン以上を保証）
        let safeDelay = max(delay, epsilon)
        
        #if DEBUG
        print("[AppModel] rescheduleBoundarySync: nextBoundary=\(nextBoundary), delay=\(String(format: "%.3f", delay))s, safeDelay=\(String(format: "%.3f", safeDelay))s")
        #endif
        
        // 常にTask.sleepでスケジュール（同期的な呼び出しを避ける）
        boundarySyncTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(safeDelay * 1_000_000_000))
                
                guard !Task.isCancelled else {
                    #if DEBUG
                    print("[AppModel] rescheduleBoundarySync: task was cancelled")
                    #endif
                    return
                }
                
                await MainActor.run {
                    #if DEBUG
                    print("[AppModel] rescheduleBoundarySync: boundary sync fired at \(Date())")
                    #endif
                    // 境界時刻が過ぎた後、同期してから次の境界時刻を再スケジュール
                    self?.syncBlocking()
                    // syncBlocking()内でrescheduleBoundarySync()が呼ばれるため、ここでは呼ばない
                }
            } catch {
                // キャンセルされた場合は何もしない
                #if DEBUG
                print("[AppModel] rescheduleBoundarySync: task sleep was cancelled")
                #endif
            }
        }
    }

    /// Downtimeのブロック条件を判定（完全に独立したシステム）
    /// - Parameter now: 判定する時刻
    /// - Returns: Downtime条件が満たされている場合true
    private func shouldBlockForDowntime(now: Date) -> Bool {
        let downtime = slot.downtime
        
        // 曜日判定
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: now)
        if let currentWeekday = Weekday(rawValue: weekday) {
            if !downtime.enabledWeekdays.contains(currentWeekday) {
                return false
            }
        }
        
        // 時間枠判定
        let comps = cal.dateComponents([.hour, .minute], from: now)
        let minutes = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)

        let start = downtime.startMinutes
        let end = downtime.endMinutes

        if start < end {
            // 同日枠: start ≤ now < end
            return minutes >= start && minutes < end
        } else if start > end {
            // 日跨ぎ枠: now ≥ start または now < end
            return minutes >= start || minutes < end
        } else {
            return false
        }
    }

    /// App Limitのブロック条件を判定（完全に独立したシステム）
    /// - Parameter now: 判定する時刻（現在は未使用、将来のDeviceActivity実装用）
    /// - Returns: App Limit条件が満たされている場合true
    /// - Note: 現在はisAppLimitReachedフラグを使用。将来はDeviceActivityで更新される
    private func shouldBlockForAppLimit(now: Date) -> Bool {
        let appLimit = slot.appLimit
        
        // 使用時間制限が有効で、Proユーザーの場合のみ
        guard isPro, let dailyLimit = appLimit.dailyLimitMinutes, dailyLimit > 0 else {
            return false
        }
        
        // 現在はisAppLimitReachedフラグを使用
        // 将来: DeviceActivity Monitorで日次使用時間を追跡し、制限に達したらtrueを返す
        return isAppLimitReached
    }
    
    /// App Limitの到達状態を更新（非推奨: App Groupから直接読み取る方式に移行）
    /// - Parameter reached: 制限に達したかどうか
    /// - Note: このメソッドは後方互換性のため残していますが、通常はApp Groupから直接読み取ります
    func updateAppLimitReached(_ reached: Bool) {
        isAppLimitReached = reached
        // App Groupにも書き込む（一貫性のため）
        UserDefaults(suiteName: "group.com.kflow.quizlock")?.set(reached, forKey: "isAppLimitReached")
        syncBlocking()  // 状態を再評価
    }

    /// ブロックを適用（DowntimeとApp Limitの和集合）
    /// - Parameters:
    ///   - shouldBlockDowntime: Downtime条件が満たされているか
    ///   - shouldBlockAppLimit: App Limit条件が満たされているか
    private func applyBlockingNow(shouldBlockDowntime: Bool, shouldBlockAppLimit: Bool) {
        var allTokens: Set<ApplicationToken> = []
        
        // Downtime用のトークンを追加
        // FreeプランでもdowntimeActivitySelectionを使用（DowntimeSettingsViewで設定される）
        // ただし、Freeプランの場合はactivitySelectionもフォールバックとして使用
        if shouldBlockDowntime {
            if !downtimeActivitySelection.applicationTokens.isEmpty {
                // downtimeActivitySelectionが設定されている場合はそれを使用
                allTokens.formUnion(downtimeActivitySelection.applicationTokens)
            } else if !activitySelection.applicationTokens.isEmpty {
                // FreeプランでdowntimeActivitySelectionが空の場合、activitySelectionを使用（後方互換性）
                allTokens.formUnion(activitySelection.applicationTokens)
            }
        }
        
        // App Limit用のトークンを追加（Proユーザーのみ）
        if shouldBlockAppLimit && isPro {
            allTokens.formUnion(appLimitActivitySelection.applicationTokens)
        }
        
        guard !allTokens.isEmpty else {
            store.shield.applications = nil
            isBlockingNow = false
            return
        }
        
        store.shield.applications = allTokens
        isBlockingNow = true
    }

    private func removeBlockingNow() {
        store.shield.applications = nil
        isBlockingNow = false
    }

    // MARK: - Quiz
    /// クイズを開始（選択されたグループの問題からランダムに選択）
    /// - Returns: 開始可能な場合は.success、不可能な場合はエラー種別
    func startQuiz() -> QuizStartResult {
        // グループが選択されているかチェック
        if pack.selectedGroupIds.isEmpty {
            return .noGroupSelected
        }
        
        // 選択されたグループに問題があるかチェック
        let availableQuestions = pack.selectedQuestions()
        if availableQuestions.isEmpty {
            return .noQuestions
        }
        
        // 制限するアプリが設定されているかチェック
        // applyBlockingNow()と同じロジックを使用
        var hasDowntimeApps = false
        if !downtimeActivitySelection.applicationTokens.isEmpty {
            // downtimeActivitySelectionが設定されている場合はそれを使用
            hasDowntimeApps = true
        } else if !activitySelection.applicationTokens.isEmpty {
            // FreeプランでdowntimeActivitySelectionが空の場合、activitySelectionを使用（後方互換性）
            hasDowntimeApps = true
        }
        
        let hasAppLimitApps = isPro && !appLimitActivitySelection.applicationTokens.isEmpty
        if !hasDowntimeApps && !hasAppLimitApps {
            return .noAppsSelected
        }
        
        // 解除中かチェック
        if let until = unlockUntil, Date() < until {
            return .unlocked
        }
        
        lastAnswerWasCorrect = nil
        correctCount = 0
        currentShuffled = pack.randomShuffled()
        return .success
    }
    
    /// クイズ開始の結果
    enum QuizStartResult {
        case success              // 開始可能
        case noGroupSelected      // グループが選択されていない
        case noQuestions         // 問題がない
        case noAppsSelected       // 制限するアプリが設定されていない
        case unlocked            // 解除中
    }

    /// 選択肢に回答（4択形式用）
    /// - Parameter choiceIndex: 選択した選択肢のインデックス（0-3）
    /// - Note: 解除条件に応じて解除時間または解除判定を行う
    func answer(choiceIndex: Int) {
        guard let q = currentShuffled, q.type == .multipleChoice else { return }

        let correct = (choiceIndex == q.correctShuffledIndex)
        lastAnswerWasCorrect = correct

        if correct {
            handleCorrectAnswer()
        } else {
            // 不正解時：次の問題を準備（UI側で遅延表示を制御）
            // 即座に次の問題を設定せず、UI側の制御に任せる
        }
    }
    
    /// テキストで回答（記述式用）
    /// - Parameter text: 入力した答え
    /// - Note: 大文字小文字・前後の空白は無視して判定
    func answerText(_ text: String) {
        guard let q = currentShuffled, q.type == .textInput,
              let correctAnswer = q.correctAnswer else { return }
        
        let correct = QuizEngine.isTextAnswerCorrect(userAnswer: text, correctAnswer: correctAnswer)
        lastAnswerWasCorrect = correct
        
        if correct {
            handleCorrectAnswer()
        } else {
            // 不正解時：次の問題を準備（UI側で遅延表示を制御）
            // 即座に次の問題を設定せず、UI側の制御に任せる
        }
    }
    
    /// 正解時の処理（解除条件に応じて処理）
    /// - Note: 問題数ベースのトリガーの場合、必要な問題数に達したらアンロック
    ///         アンロック期間は常にunlockDurationMinutesを使用
    private func handleCorrectAnswer() {
        correctCount += 1
        
        switch slot.unlockTrigger {
        case .immediate:
            // 即座にアンロック（unlockDurationMinutes分）
            unlockUntil = Date().addingTimeInterval(TimeInterval(slot.unlockDurationMinutes * 60))
            scheduleUnlockTimer()
            persistAll()
            // syncBlocking()内でrescheduleBoundarySync()が呼ばれるため、重複呼び出しを避ける
            syncBlocking()
            // クイズ画面を閉じる
            shouldDismissQuiz = true
            
        case .questionCount(let required):
            // 問題数ベース：指定問題数正解するとアンロック
            if correctCount >= required {
                // 必要問題数に達したらアンロック（unlockDurationMinutes分）
                unlockUntil = Date().addingTimeInterval(TimeInterval(slot.unlockDurationMinutes * 60))
                scheduleUnlockTimer()
                setupUnlockSchedule(unlockUntil: unlockUntil)  // Unlock用のDeviceActivityスケジュールを設定
                persistAll()
                correctCount = 0  // リセット
                // syncBlocking()内でrescheduleBoundarySync()が呼ばれるため、重複呼び出しを避ける
                syncBlocking()
                // クイズ画面を閉じる
                shouldDismissQuiz = true
            }
        }
    }
    
    /// アンロックタイマーをスケジュール（期限が過ぎたら自動的に再ロック）
    private func scheduleUnlockTimer() {
        // 既存のタイマータスクをキャンセル
        unlockTimerTask?.cancel()
        
        guard let until = unlockUntil else { return }
        
        let now = Date()
        guard until > now else { return }
        
        let delay = until.timeIntervalSince(now)
        
        unlockTimerTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                
                // タイマーがキャンセルされていない場合のみ実行
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    self?.syncBlocking()
                }
            } catch {
                // キャンセルされた場合は何もしない
            }
        }
    }
    
    /// 次の問題へ進む（不正解時のUI制御用）
    func nextQuestion() {
        lastAnswerWasCorrect = nil
        currentShuffled = pack.randomShuffled()
    }
    
    /// スキップ機能：問題を解かずに解除
    func skipQuestion() {
        // スキップ機能が有効な場合のみ実行
        guard slot.isSkipEnabled else { return }
        
        // 正解時と同じ処理を実行
        switch slot.unlockTrigger {
        case .immediate:
            // 即座にアンロック（unlockDurationMinutes分）
            unlockUntil = Date().addingTimeInterval(TimeInterval(slot.unlockDurationMinutes * 60))
            scheduleUnlockTimer()
            setupUnlockSchedule(unlockUntil: unlockUntil)  // Unlock用のDeviceActivityスケジュールを設定
            persistAll()
            // syncBlocking()内でrescheduleBoundarySync()が呼ばれるため、重複呼び出しを避ける
            syncBlocking()
            // クイズ画面を閉じる
            shouldDismissQuiz = true
            
        case .questionCount(let required):
            // 問題数ベース：1問正解として扱う
            correctCount += 1
            if correctCount >= required {
                unlockUntil = Date().addingTimeInterval(TimeInterval(slot.unlockDurationMinutes * 60))
                scheduleUnlockTimer()
                setupUnlockSchedule(unlockUntil: unlockUntil)  // Unlock用のDeviceActivityスケジュールを設定
                persistAll()
                correctCount = 0
                // syncBlocking()内でrescheduleBoundarySync()が呼ばれるため、重複呼び出しを避ける
                syncBlocking()
                // クイズ画面を閉じる
                shouldDismissQuiz = true
        } else {
                persistAll()
            }
        }
        
        // 次の問題へ（アンロック条件が満たされていない場合のみ）
        if !shouldDismissQuiz {
            lastAnswerWasCorrect = true  // スキップは正解として扱う
            currentShuffled = pack.randomShuffled()
        }
    }

    /// 解除条件を更新（新しいAPI：durationMinutesとrequiredQuestionsの両方が必須）
    /// - Note: requiredQuestionsが1の場合はimmediateトリガー、それ以外はquestionCountトリガー
    func updateUnlockCondition(durationMinutes: Int, requiredQuestions: Int, isSkipEnabled: Bool? = nil) {
        // アンロック期間を設定（常に存在）
        slot.unlockDurationMinutes = durationMinutes
        
        // アンロックトリガーを設定
        // requiredQuestionsが1の場合は即座にアンロック、それ以外は問題数ベース
        if requiredQuestions == 1 {
            slot.unlockTrigger = .immediate
        } else {
            // 無課金ユーザーは10問まで、課金ユーザーは100問まで
            let maxQuestions = isPro ? 100 : 10
            let clampedQuestions = min(requiredQuestions, maxQuestions)
            slot.unlockTrigger = .questionCount(required: clampedQuestions)
        }
        
        if let skip = isSkipEnabled {
            slot.isSkipEnabled = skip
        }
        persistAll()
        syncBlocking()
    }
    
    // 後方互換性のためのメソッド
    func updateUnlockCondition(type: UnlockConditionType, durationMinutes: Int? = nil, requiredQuestions: Int? = nil, isSkipEnabled: Bool? = nil) {
        // 古いenumから新しいenumに変換
        slot.unlockTrigger = type
        
        if let duration = durationMinutes {
            slot.unlockDurationMinutes = duration
        }
        
        if let questions = requiredQuestions {
            // 無課金ユーザーは10問まで、課金ユーザーは100問まで
            let maxQuestions = isPro ? 100 : 10
            let clampedQuestions = min(questions, maxQuestions)
            slot.unlockTrigger = .questionCount(required: clampedQuestions)
        }
        
        if let skip = isSkipEnabled {
            slot.isSkipEnabled = skip
        }
        persistAll()
        syncBlocking()
    }

    // MARK: - Questions CRUD
    /// 問題を追加
    func addQuestion(_ q: Question) {
        pack.questions.append(q)
        pack.updatedAt = Date()
        persistAll()
    }

    /// 問題を更新（UUIDで識別）
    func updateQuestion(_ q: Question) {
        guard let idx = pack.questions.firstIndex(where: { $0.id == q.id }) else { return }
        pack.questions[idx] = q
        pack.updatedAt = Date()
        persistAll()
    }

    /// 問題を削除（QuestionListView の `.onDelete(perform:)` 用）
    func deleteQuestion(at offsets: IndexSet) {
        let deletedIds = offsets.map { pack.questions[$0].id }
        pack.questions.remove(atOffsets: offsets)
        // 削除された問題をグループからも削除
        for i in pack.groups.indices {
            pack.groups[i].questionIds.removeAll { deletedIds.contains($0) }
        }
        pack.updatedAt = Date()
        persistAll()
    }
    
    /// 問題を削除（UUID配列で指定）
    func deleteQuestion(ids: [UUID]) {
        let deletedIds = Set(ids)
        pack.questions.removeAll { deletedIds.contains($0.id) }
        // 削除された問題をグループからも削除
        for i in pack.groups.indices {
            pack.groups[i].questionIds.removeAll { deletedIds.contains($0) }
        }
        pack.updatedAt = Date()
        persistAll()
    }
    
    // MARK: - Groups CRUD
    /// グループを追加
    func addGroup(_ group: QuestionGroup) {
        pack.groups.append(group)
        pack.updatedAt = Date()
        persistAll()
    }
    
    /// グループを更新
    func updateGroup(_ group: QuestionGroup) {
        guard let idx = pack.groups.firstIndex(where: { $0.id == group.id }) else { return }
        pack.groups[idx] = group
        pack.updatedAt = Date()
        persistAll()
    }
    
    /// グループを削除（グループに属するすべての問題も削除される）
    /// - Note: グループ削除時は、そのグループに属するすべての問題も削除されます。
    ///   未分類の問題は存在しません。すべての問題は常に少なくとも1つのグループに属する必要があります。
    func deleteGroup(_ groupId: UUID) {
        guard let group = pack.groups.first(where: { $0.id == groupId }) else { return }
        
        // Delete all questions belonging to this group
        // This ensures no orphan questions exist after group deletion
        deleteQuestion(ids: group.questionIds)
        
        // Remove the group
        pack.groups.removeAll { $0.id == groupId }
        pack.selectedGroupIds.removeAll { $0 == groupId }
        pack.updatedAt = Date()
        persistAll()
    }
    
    /// グループの選択状態を更新
    func toggleGroupSelection(_ groupId: UUID) {
        if pack.selectedGroupIds.contains(groupId) {
            pack.selectedGroupIds.removeAll { $0 == groupId }
        } else {
            pack.selectedGroupIds.append(groupId)
        }
        pack.updatedAt = Date()
        persistAll()
    }
    
    /// グループが選択されているか
    func isGroupSelected(_ groupId: UUID) -> Bool {
        pack.selectedGroupIds.contains(groupId)
    }
    
    /// 問題をグループに追加
    func addQuestionToGroup(questionId: UUID, groupId: UUID) {
        guard let idx = pack.groups.firstIndex(where: { $0.id == groupId }) else { return }
        if !pack.groups[idx].questionIds.contains(questionId) {
            pack.groups[idx].questionIds.append(questionId)
            pack.updatedAt = Date()
            persistAll()
        }
    }
    
    /// 問題をグループから削除
    func removeQuestionFromGroup(questionId: UUID, groupId: UUID) {
        guard let idx = pack.groups.firstIndex(where: { $0.id == groupId }) else { return }
        pack.groups[idx].questionIds.removeAll { $0 == questionId }
        pack.updatedAt = Date()
        persistAll()
    }
    
    // MARK: - Question Move/Copy
    /// 問題をグループ間で移動
    /// - Note: add-first-then-remove パターンで安全に移動します。
    ///   同じグループへの移動は無視されます。
    func moveQuestion(questionId: UUID, fromGroupId: UUID, toGroupId: UUID) {
        // Guard: 同じグループへの移動は無視
        guard fromGroupId != toGroupId else { return }
        
        // Guard: 両方のグループが存在することを確認
        guard pack.groups.contains(where: { $0.id == fromGroupId }),
              pack.groups.contains(where: { $0.id == toGroupId }) else { return }
        
        // Guard: 問題が存在することを確認
        guard pack.questions.contains(where: { $0.id == questionId }) else { return }
        
        // Add first, then remove (safe pattern)
        addQuestionToGroup(questionId: questionId, groupId: toGroupId)
        removeQuestionFromGroup(questionId: questionId, groupId: fromGroupId)
    }
    
    /// 問題をコピーしてグループに追加
    /// - Returns: コピーされた問題（新しいUUID）
    func copyQuestion(questionId: UUID, toGroupIds: [UUID]) -> Question? {
        guard let originalQuestion = pack.questions.first(where: { $0.id == questionId }) else { return nil }
        
        // 新しいUUIDで問題をコピー
        var copiedQuestion: Question
        if originalQuestion.type == .multipleChoice {
            copiedQuestion = Question(
                questionText: originalQuestion.questionText,
                choices: originalQuestion.choices ?? [],
                correctIndex: originalQuestion.correctIndex ?? 0,
                hint: originalQuestion.hint
            )
        } else {
            copiedQuestion = Question(
                questionText: originalQuestion.questionText,
                correctAnswer: originalQuestion.correctAnswer ?? "",
                hint: originalQuestion.hint
            )
        }
        
        // 問題を追加
        addQuestion(copiedQuestion)
        
        // 指定されたグループに追加
        for groupId in toGroupIds {
            addQuestionToGroup(questionId: copiedQuestion.id, groupId: groupId)
        }
        
        return copiedQuestion
    }
    
    /// 複数問題をグループ間で移動
    /// - Note: すべての問題を安全に移動します（add-first-then-remove パターン）
    ///   各問題IDに対して個別に検証を行い、存在しない問題はスキップします。
    func moveQuestions(questionIds: [UUID], fromGroupId: UUID, toGroupId: UUID) {
        // Guard: 同じグループへの移動は無視
        guard fromGroupId != toGroupId else {
            #if DEBUG
            print("⚠️ [AppModel] moveQuestions: skipping move to same group")
            #endif
            return
        }
        
        // Guard: 両方のグループが存在することを確認
        guard pack.groups.contains(where: { $0.id == fromGroupId }),
              pack.groups.contains(where: { $0.id == toGroupId }) else {
            #if DEBUG
            print("❌ [AppModel] moveQuestions: source or destination group does not exist")
            #endif
            return
        }
        
        // Filter valid question IDs (must exist in pack.questions)
        let validQuestionIds = questionIds.filter { questionId in
            pack.questions.contains(where: { $0.id == questionId })
        }
        
        guard !validQuestionIds.isEmpty else {
            #if DEBUG
            print("⚠️ [AppModel] moveQuestions: no valid questions to move")
            #endif
            return
        }
        
        if validQuestionIds.count != questionIds.count {
            #if DEBUG
            print("⚠️ [AppModel] moveQuestions: \(questionIds.count - validQuestionIds.count) invalid question IDs skipped")
            #endif
        }
        
        #if DEBUG
        print("✅ [AppModel] moveQuestions: moving \(validQuestionIds.count) questions from \(fromGroupId) to \(toGroupId)")
        #endif
        
        // Add all questions to destination first (per question, to avoid transient orphan states)
        for questionId in validQuestionIds {
            addQuestionToGroup(questionId: questionId, groupId: toGroupId)
        }
        
        // Then remove all from source
        for questionId in validQuestionIds {
            removeQuestionFromGroup(questionId: questionId, groupId: fromGroupId)
        }
        
        // Ensure persistence
        persistAll()
        #if DEBUG
        print("✅ [AppModel] moveQuestions: operation completed and persisted")
        #endif
    }
    
    /// 複数問題をコピーしてグループに追加
    /// - Note: 各問題IDに対して個別に検証を行い、存在しない問題はスキップします。
    /// - Returns: コピーされた問題の配列
    func copyQuestions(questionIds: [UUID], toGroupIds: [UUID]) -> [Question] {
        // Guard: destination groups must exist
        guard !toGroupIds.isEmpty else {
            #if DEBUG
            print("❌ [AppModel] copyQuestions: no destination groups provided")
            #endif
            return []
        }
        
        // Verify all destination groups exist
        for groupId in toGroupIds {
            guard pack.groups.contains(where: { $0.id == groupId }) else {
                #if DEBUG
                print("❌ [AppModel] copyQuestions: destination group does not exist: \(groupId)")
                #endif
                return []
            }
        }
        
        // Filter valid question IDs
        let validQuestionIds = questionIds.filter { questionId in
            pack.questions.contains(where: { $0.id == questionId })
        }
        
        guard !validQuestionIds.isEmpty else {
            #if DEBUG
            print("⚠️ [AppModel] copyQuestions: no valid questions to copy")
            #endif
            return []
        }
        
        if validQuestionIds.count != questionIds.count {
            #if DEBUG
            print("⚠️ [AppModel] copyQuestions: \(questionIds.count - validQuestionIds.count) invalid question IDs skipped")
            #endif
        }
        
        #if DEBUG
        print("✅ [AppModel] copyQuestions: copying \(validQuestionIds.count) questions to \(toGroupIds.count) groups")
        #endif
        
        var copiedQuestions: [Question] = []
        for questionId in validQuestionIds {
            if let copied = copyQuestion(questionId: questionId, toGroupIds: toGroupIds) {
                copiedQuestions.append(copied)
            }
        }
        
        // Ensure persistence
        persistAll()
        #if DEBUG
        print("✅ [AppModel] copyQuestions: operation completed and persisted, created \(copiedQuestions.count) copies")
        #endif
        
        return copiedQuestions
    }
    
    /// グループをコピー
    /// - Returns: コピーされたグループ
    func copyGroup(groupId: UUID) -> QuestionGroup? {
        guard let originalGroup = pack.groups.first(where: { $0.id == groupId }) else { return nil }
        
        // グループ内の全問題をコピー（一時的に空の配列にコピー）
        let copiedQuestions = copyQuestions(questionIds: originalGroup.questionIds, toGroupIds: [])
        let copiedQuestionIds = copiedQuestions.map { $0.id }
        
        // 新しいグループを作成
        let copiedGroup = QuestionGroup(
            name: "\(originalGroup.name) コピー",
            questionIds: copiedQuestionIds
        )
        
        // グループを追加（questionIdsは既に設定済み）
        addGroup(copiedGroup)
        
        return copiedGroup
    }
    // MARK: - Screen Time Authorization
    /// ユーザーにScreen Time権限を要求
    /// - Note: 権限要求後に状態を自動更新
        func requestScreenTimeAuthorizationFromUser() async {
            let center = AuthorizationCenter.shared
            do {
                try await center.requestAuthorization(for: .individual)
            // 権限要求後に状態を更新
            screenTimeAuthStatus = center.authorizationStatus
            } catch {
                // 失敗しても何もしない（UX的にOK）
            #if DEBUG
                print("Screen Time auth failed:", error)
            #endif
        }
    }
    
    /// Screen Time権限状態を最新の状態に同期
    /// - Note: アプリ起動時・復帰時に呼ばれる
    func syncScreenTimeAuthStatus() {
        screenTimeAuthStatus = AuthorizationCenter.shared.authorizationStatus
    }
    
    /// 設定アプリ誘導が必要か（権限が拒否されている場合）
    var needsOpenSettings: Bool {
        screenTimeAuthStatus == .denied
    }
}
