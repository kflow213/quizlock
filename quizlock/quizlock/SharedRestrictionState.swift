import Foundation
import FamilyControls

/// App Group経由で共有される制限状態（ExtensionとAppの間で共有）
/// - Note: ExtensionはUserDefaults.standardにアクセスできないため、App Groupを使用
struct SharedRestrictionState {
    private static let appGroupIdentifier = "group.com.kflow.quizlock"
    
    // App Groupのキー
    private static let lockSlotKey = "lockSlot_v1"
    private static let downtimeSelectionKey = "downtimeSelection_v1"
    private static let appLimitSelectionKey = "appLimitSelection_v1"
    private static let fallbackSelectionKey = "fallbackSelection_v1"
    private static let unlockUntilKey = "unlockUntil_v1"
    private static let isProKey = "isPro_v1"
    private static let isAppLimitReachedKey = "isAppLimitReached"  // 既存のキーと互換性を保つ
    
    private static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }
    
    // MARK: - Save to App Group
    
    /// 制限状態をApp Groupに保存
    static func save(
        lockSlot: LockSlot,
        downtimeSelection: FamilyActivitySelection,
        appLimitSelection: FamilyActivitySelection,
        fallbackSelection: FamilyActivitySelection,
        unlockUntil: Date?,
        isPro: Bool
    ) {
        guard let defaults = sharedDefaults else {
            #if DEBUG
            print("[SharedRestrictionState] Failed to access App Group UserDefaults")
            #endif
            return
        }
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        // LockSlotを保存
        if let data = try? encoder.encode(lockSlot) {
            defaults.set(data, forKey: lockSlotKey)
        }
        
        // Selectionsを保存
        if let data = try? encoder.encode(downtimeSelection) {
            defaults.set(data, forKey: downtimeSelectionKey)
        }
        if let data = try? encoder.encode(appLimitSelection) {
            defaults.set(data, forKey: appLimitSelectionKey)
        }
        if let data = try? encoder.encode(fallbackSelection) {
            defaults.set(data, forKey: fallbackSelectionKey)
        }
        
        // unlockUntilを保存（timeIntervalSince1970として）
        if let unlockUntil = unlockUntil {
            defaults.set(unlockUntil.timeIntervalSince1970, forKey: unlockUntilKey)
        } else {
            defaults.removeObject(forKey: unlockUntilKey)
        }
        
        // isProを保存
        defaults.set(isPro, forKey: isProKey)
        
        defaults.synchronize()
        
        #if DEBUG
        print("[SharedRestrictionState] Saved restriction state to App Group")
        #endif
    }
    
    // MARK: - Load from App Group
    
    /// App Groupから制限状態を読み込む
    static func load() -> (
        lockSlot: LockSlot?,
        downtimeSelection: FamilyActivitySelection?,
        appLimitSelection: FamilyActivitySelection?,
        fallbackSelection: FamilyActivitySelection?,
        unlockUntil: Date?,
        isPro: Bool,
        isAppLimitReached: Bool
    ) {
        guard let defaults = sharedDefaults else {
            #if DEBUG
            print("[SharedRestrictionState] Failed to access App Group UserDefaults")
            #endif
            return (nil, nil, nil, nil, nil, false, false)
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
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
