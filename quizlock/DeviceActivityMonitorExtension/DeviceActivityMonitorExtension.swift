//
//  DeviceActivityMonitorExtension.swift
//  DeviceActivityMonitorExtension
//
//  Created by 小花昌司 on 2026/01/11.
//

import Foundation
import DeviceActivity
import ManagedSettings
import FamilyControls
import os

/// DeviceActivity Monitor Extension
/// OSレベルで制限を強制する（アプリが開かれていなくても動作）
/// 
/// 注意: NotificationCenterは別プロセス間で動作しないため、App Groupを使用して状態を共有します。
nonisolated class AppLimitMonitor: DeviceActivityMonitor {
    private let logger = Logger(subsystem: "com.kflow.quizlock.DeviceActivityMonitorExtension", category: "AppLimitMonitor")
    private let appGroupIdentifier = "group.com.kflow.quizlock"
    private let store = ManagedSettingsStore()
    
    // DeviceActivityNameの定義（AppModelと一致させる必要がある）
    private static let appLimitScheduleName = DeviceActivityName("appLimitSchedule")
    private static let downtimeScheduleName = DeviceActivityName("downtimeSchedule")
    private static let downtimeScheduleOvernightName = DeviceActivityName("downtimeScheduleOvernight")
    private static let unlockWindowName = DeviceActivityName("unlockWindow")
    
    // MARK: - Interval Callbacks
    
    nonisolated override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        #if DEBUG
        logger.info("intervalDidStart: \(activity.rawValue)")
        #endif
        
        switch activity {
        case Self.appLimitScheduleName:
            // 日次リセット：App Limitの状態をリセット
            resetDailyUsage()
            applyShieldForCurrentState(reason: "App Limit interval started")
            
        case Self.downtimeScheduleName, Self.downtimeScheduleOvernightName:
            // Downtime開始：Shieldを適用
            applyShieldForCurrentState(reason: "Downtime interval started: \(activity.rawValue)")
            
        case Self.unlockWindowName:
            // Unlock開始：Shieldを削除
            removeShield(reason: "Unlock window started")
            
        default:
            #if DEBUG
            logger.warning("Unknown activity: \(activity.rawValue)")
            #endif
        }
    }
    
    nonisolated override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        #if DEBUG
        logger.info("intervalDidEnd: \(activity.rawValue)")
        #endif
        
        switch activity {
        case Self.appLimitScheduleName:
            // 日次リセット：App Limitの状態をリセット
            resetDailyUsage()
            applyShieldForCurrentState(reason: "App Limit interval ended")
            
        case Self.downtimeScheduleName, Self.downtimeScheduleOvernightName:
            // Downtime終了：Shieldを再評価
            applyShieldForCurrentState(reason: "Downtime interval ended: \(activity.rawValue)")
            
        case Self.unlockWindowName:
            // Unlock期限切れ：Shieldを再適用
            applyShieldForCurrentState(reason: "Unlock window ended - re-locking")
            
        default:
            #if DEBUG
            logger.warning("Unknown activity: \(activity.rawValue)")
            #endif
        }
    }
    
    nonisolated override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        #if DEBUG
        logger.info("eventDidReachThreshold: event=\(event.rawValue), activity=\(activity.rawValue)")
        #endif
        
        // App Limitに到達：即座にShieldを適用
        if activity == Self.appLimitScheduleName {
            if let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) {
                sharedDefaults.set(true, forKey: "isAppLimitReached")
                sharedDefaults.set(Date().timeIntervalSince1970, forKey: "appLimitReachedTimestamp")
                sharedDefaults.synchronize()
                #if DEBUG
                logger.info("App Limit reached - wrote to App Group and applying shield")
                #endif
            }
            applyShieldForCurrentState(reason: "App Limit threshold reached")
        }
    }
    
    // MARK: - Shield Management
    
    /// 現在の状態に基づいてShieldを適用/削除
    private func applyShieldForCurrentState(reason: String) {
        #if DEBUG
        logger.info("applyShieldForCurrentState: \(reason)")
        #endif
        
        let state = loadRestrictionState()
        
        guard let lockSlot = state.lockSlot else {
            #if DEBUG
            logger.warning("No lockSlot found in App Group - removing shield")
            #endif
            removeShield(reason: "No lockSlot")
            return
        }
        
        let now = Date()
        
        // 1. Unlock中かチェック
        if let unlockUntil = state.unlockUntil, now < unlockUntil {
            // Unlock中：すべてのShieldを削除
            removeShield(reason: "Unlocked until \(unlockUntil)")
            return
        }
        
        // 2. Downtimeをチェック
        let shouldBlockDowntime = shouldBlockForDowntime(
            downtime: lockSlot.downtime,
            now: now
        )
        
        // 3. App Limitをチェック
        let shouldBlockAppLimit = shouldBlockForAppLimit(
            isPro: state.isPro,
            dailyLimitMinutes: lockSlot.appLimit.dailyLimitMinutes,
            isAppLimitReached: state.isAppLimitReached
        )
        
        // 4. Shieldを適用
        if shouldBlockDowntime || shouldBlockAppLimit {
            applyShield(
                shouldBlockDowntime: shouldBlockDowntime,
                shouldBlockAppLimit: shouldBlockAppLimit,
                downtimeSelection: state.downtimeSelection,
                appLimitSelection: state.appLimitSelection,
                fallbackSelection: state.fallbackSelection,
                isPro: state.isPro,
                reason: reason
            )
        } else {
            removeShield(reason: "No restrictions active")
        }
    }
    
    /// Shieldを削除
    private func removeShield(reason: String) {
        #if DEBUG
        logger.info("removeShield: \(reason)")
        #endif
        store.shield.applications = nil
    }
    
    /// Shieldを適用
    private func applyShield(
        shouldBlockDowntime: Bool,
        shouldBlockAppLimit: Bool,
        downtimeSelection: FamilyActivitySelection?,
        appLimitSelection: FamilyActivitySelection?,
        fallbackSelection: FamilyActivitySelection?,
        isPro: Bool,
        reason: String
    ) {
        var allTokens: Set<ApplicationToken> = []
        
        // Downtime用のトークンを追加
        if shouldBlockDowntime {
            if let downtimeSelection = downtimeSelection, !downtimeSelection.applicationTokens.isEmpty {
                allTokens.formUnion(downtimeSelection.applicationTokens)
            } else if let fallbackSelection = fallbackSelection, !fallbackSelection.applicationTokens.isEmpty {
                // フォールバック（後方互換性）
                allTokens.formUnion(fallbackSelection.applicationTokens)
            }
        }
        
        // App Limit用のトークンを追加（Proユーザーのみ）
        if shouldBlockAppLimit && isPro {
            if let appLimitSelection = appLimitSelection {
                allTokens.formUnion(appLimitSelection.applicationTokens)
            }
        }
        
        guard !allTokens.isEmpty else {
            #if DEBUG
            logger.warning("No tokens to shield - removing shield")
            #endif
            removeShield(reason: "No tokens available")
            return
        }
        
        store.shield.applications = allTokens
        #if DEBUG
        logger.info("Shield applied: \(allTokens.count) apps, reason: \(reason)")
        #endif
    }
    
    // MARK: - Blocking Logic (AppModelと同じロジック)
    
    /// Downtimeのブロック条件を判定
    private func shouldBlockForDowntime(downtime: DowntimeSettings, now: Date) -> Bool {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: now)
        
        // 曜日判定
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
    
    /// App Limitのブロック条件を判定
    private func shouldBlockForAppLimit(isPro: Bool, dailyLimitMinutes: Int?, isAppLimitReached: Bool) -> Bool {
        guard isPro, let dailyLimit = dailyLimitMinutes, dailyLimit > 0 else {
            return false
        }
        return isAppLimitReached
    }
    
    // MARK: - Daily Usage Reset
    
    private func resetDailyUsage() {
        if let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) {
            sharedDefaults.set(false, forKey: "isAppLimitReached")
            sharedDefaults.removeObject(forKey: "appLimitReachedTimestamp")
            sharedDefaults.synchronize()
            #if DEBUG
            logger.info("Daily usage reset - wrote to App Group")
            #endif
        } else {
            #if DEBUG
            logger.error("Failed to access App Group UserDefaults for reset")
            #endif
        }
    }
    
    // MARK: - App Group State Loading
    
    /// App Groupから制限状態を読み込む（Extension内で使用）
    private func loadRestrictionState() -> (
        lockSlot: LockSlot?,
        downtimeSelection: FamilyActivitySelection?,
        appLimitSelection: FamilyActivitySelection?,
        fallbackSelection: FamilyActivitySelection?,
        unlockUntil: Date?,
        isPro: Bool,
        isAppLimitReached: Bool
    ) {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else {
            #if DEBUG
            logger.error("Failed to access App Group UserDefaults")
            #endif
            return (nil, nil, nil, nil, nil, false, false)
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        // App Groupのキー
        let lockSlotKey = "lockSlot_v1"
        let downtimeSelectionKey = "downtimeSelection_v1"
        let appLimitSelectionKey = "appLimitSelection_v1"
        let fallbackSelectionKey = "fallbackSelection_v1"
        let unlockUntilKey = "unlockUntil_v1"
        let isProKey = "isPro_v1"
        let isAppLimitReachedKey = "isAppLimitReached"
        
        // LockSlotを読み込む
        let lockSlot: LockSlot? = {
            guard let data = defaults.data(forKey: lockSlotKey),
                  let slot = try? decoder.decode(LockSlot.self, from: data) else {
                return nil
            }
            return slot
        }()
        
        // Selectionsを読み込む
        let downtimeSelection: FamilyActivitySelection? = {
            guard let data = defaults.data(forKey: downtimeSelectionKey),
                  let selection = try? decoder.decode(FamilyActivitySelection.self, from: data) else {
                return nil
            }
            return selection
        }()
        
        let appLimitSelection: FamilyActivitySelection? = {
            guard let data = defaults.data(forKey: appLimitSelectionKey),
                  let selection = try? decoder.decode(FamilyActivitySelection.self, from: data) else {
                return nil
            }
            return selection
        }()
        
        let fallbackSelection: FamilyActivitySelection? = {
            guard let data = defaults.data(forKey: fallbackSelectionKey),
                  let selection = try? decoder.decode(FamilyActivitySelection.self, from: data) else {
                return nil
            }
            return selection
        }()
        
        // unlockUntilを読み込む
        let unlockUntil: Date? = {
            let interval = defaults.double(forKey: unlockUntilKey)
            guard interval > 0 else { return nil }
            let date = Date(timeIntervalSince1970: interval)
            return date > Date() ? date : nil  // 過去の日付は無視
        }()
        
        // isProを読み込む
        let isPro = defaults.bool(forKey: isProKey)
        
        // isAppLimitReachedを読み込む（既存のキー）
        let isAppLimitReached = defaults.bool(forKey: isAppLimitReachedKey)
        
        return (lockSlot, downtimeSelection, appLimitSelection, fallbackSelection, unlockUntil, isPro, isAppLimitReached)
    }
}

// MARK: - Supporting Types (Extension内で使用)

/// Weekday enum（Extension内で使用するため）
enum Weekday: Int, Codable, CaseIterable {
    case sunday = 1
    case monday = 2
    case tuesday = 3
    case wednesday = 4
    case thursday = 5
    case friday = 6
    case saturday = 7
}

/// DowntimeSettings（Extension内で使用するため）
struct DowntimeSettings: Codable, Equatable {
    var startMinutes: Int
    var endMinutes: Int
    var enabledWeekdays: Set<Weekday>
}

/// AppLimitSettings（Extension内で使用するため）
struct AppLimitSettings: Codable, Equatable {
    var dailyLimitMinutes: Int?
}

/// LockSlot（Extension内で使用するため）
struct LockSlot: Codable, Equatable {
    var downtime: DowntimeSettings
    var appLimit: AppLimitSettings
    var unlockTrigger: UnlockTrigger
    var unlockDurationMinutes: Int
    var isSkipEnabled: Bool
}

/// UnlockTrigger（Extension内で使用するため）
enum UnlockTrigger: Codable, Equatable {
    case immediate
    case questionCount(required: Int)
    
    enum CodingKeys: String, CodingKey {
        case type
        case required
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
        switch type {
        case "immediate":
            self = .immediate
        case "questionCount":
            let required = try container.decode(Int.self, forKey: .required)
            self = .questionCount(required: required)
        default:
            self = .immediate
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .immediate:
            try container.encode("immediate", forKey: .type)
        case .questionCount(let required):
            try container.encode("questionCount", forKey: .type)
            try container.encode(required, forKey: .required)
        }
    }
}
