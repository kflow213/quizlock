import Foundation
import DeviceActivity
import ManagedSettings

/// DeviceActivity Monitor Extension
/// 日次使用時間を追跡し、制限に達したらAppModelに通知
/// 
/// 注意: このクラスはDeviceActivity Monitor Extensionターゲットで使用されます。
/// MainActorの分離を避けるため、@MainActorを付けていません。
nonisolated class AppLimitMonitor: DeviceActivityMonitor {
    let store = ManagedSettingsStore()
    
    // 日次制限（分単位）を取得
    private var dailyLimitMinutes: Int? {
        UserDefaults(suiteName: "group.com.kflow.quizlock")?.integer(forKey: "dailyLimitMinutes")
    }
    
    nonisolated override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        // インターバル開始時にリセット
        resetDailyUsage()
    }
    
    nonisolated override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        // インターバル終了時にリセット
        resetDailyUsage()
    }
    
    nonisolated override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        
        // 制限に達したことを通知
        NotificationCenter.default.post(
            name: NSNotification.Name("AppLimitReached"),
            object: nil
        )
        
        // AppModelに通知（UserDefaults経由）
        UserDefaults(suiteName: "group.com.kflow.quizlock")?.set(true, forKey: "isAppLimitReached")
    }
    
    private func resetDailyUsage() {
        UserDefaults(suiteName: "group.com.kflow.quizlock")?.set(false, forKey: "isAppLimitReached")
        NotificationCenter.default.post(
            name: NSNotification.Name("AppLimitReset"),
            object: nil
        )
    }
}
