import Foundation
import FamilyControls

/// アプリデータの永続化（UserDefaults使用）
/// - Note: 問題データはローカル保存、UUID + schemaVersion による管理
enum AppStorageIO {
    private static let packKey = "pack_v2"  // v2: グループ機能追加
    private static let slotKey = "slot_v1"
    private static let selectionKey = "selection_v1"
    private static let downtimeSelectionKey = "downtime_selection_v1"
    private static let appLimitSelectionKey = "applimit_selection_v1"
    private static let unlockUntilKey = "unlockUntil_v1"

    struct Loaded {
        let pack: QuestionPack
        let slot: LockSlot
        let selection: FamilyActivitySelection
        let downtimeSelection: FamilyActivitySelection
        let appLimitSelection: FamilyActivitySelection
        let unlockUntil: Date?
    }

    static func save(pack: QuestionPack, slot: LockSlot, selection: FamilyActivitySelection, downtimeSelection: FamilyActivitySelection, appLimitSelection: FamilyActivitySelection, unlockUntil: Date?) {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601

        if let data = try? enc.encode(pack) {
            UserDefaults.standard.set(data, forKey: packKey)
        }
        if let data = try? enc.encode(slot) {
            UserDefaults.standard.set(data, forKey: slotKey)
        }
        if let data = try? enc.encode(selection) {
            UserDefaults.standard.set(data, forKey: selectionKey)
        }
        if let data = try? enc.encode(downtimeSelection) {
            UserDefaults.standard.set(data, forKey: downtimeSelectionKey)
        }
        if let data = try? enc.encode(appLimitSelection) {
            UserDefaults.standard.set(data, forKey: appLimitSelectionKey)
        }
        if let unlockUntil = unlockUntil {
            UserDefaults.standard.set(unlockUntil, forKey: unlockUntilKey)
        } else {
            UserDefaults.standard.removeObject(forKey: unlockUntilKey)
        }
    }

    static func load() -> Loaded {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601

        let pack: QuestionPack = {
            // v2のキーで読み込み
            if let data = UserDefaults.standard.data(forKey: packKey),
               let v = try? dec.decode(QuestionPack.self, from: data) {
                return v
            }
            // v1のキーで読み込み（互換性）
            if let data = UserDefaults.standard.data(forKey: "pack_v1"),
               let v = try? dec.decode(QuestionPack.self, from: data) {
                // v1からv2へのマイグレーション（groupsとselectedGroupIdsを追加）
                var migrated = v
                if migrated.schemaVersion < 2 {
                    migrated = QuestionPack(
                        schemaVersion: 2,
                        questions: migrated.questions,
                        groups: [],
                        selectedGroupIds: [],
                        updatedAt: migrated.updatedAt
                    )
                }
                return migrated
            }
            return .defaultPack
        }()
        
        let slot: LockSlot = {
            let customDec = JSONDecoder()
            customDec.dateDecodingStrategy = .iso8601
            
            guard let data = UserDefaults.standard.data(forKey: slotKey) else {
                return LockSlot()  // デフォルト値
            }
            
            // 新しい構造でデコードを試行
            if let v = try? dec.decode(LockSlot.self, from: data) {
                var migrated = v
                // 解除条件が設定されていない場合はデフォルト値を設定
                if migrated.unlockDurationMinutes == 0 {
                    migrated.unlockDurationMinutes = 10
                }
                // unlockTriggerがquestionCountでrequiredが0以下の場合はデフォルト値を設定
                if case .questionCount(let required) = migrated.unlockTrigger, required <= 0 {
                    migrated.unlockTrigger = .questionCount(required: 1)
                }
                return migrated
            }
            
            // 旧構造からのマイグレーション（後方互換性）
            // 旧構造を直接読み込んで新構造に変換
            if let jsonString = String(data: data, encoding: .utf8) {
                // customをdowntimeに置換
                let migratedJson = jsonString.replacingOccurrences(of: "\"custom\"", with: "\"downtime\"")
                if let jsonData = migratedJson.data(using: .utf8) {
                    // 旧構造のキーを直接読み取る
                    if let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                        let startMinutes = json["startMinutes"] as? Int ?? 19 * 60
                        let endMinutes = json["endMinutes"] as? Int ?? 22 * 60
                        let dailyLimitMinutes = json["dailyLimitMinutes"] as? Int
                        let unlockDurationMinutes = json["unlockDurationMinutes"] as? Int ?? 10
                        let unlockRequiredQuestions = json["unlockRequiredQuestions"] as? Int ?? 1
                        
                        // enabledWeekdaysの復元
                        var weekdays = Set(Weekday.allCases)
                        if let weekdaysData = json["enabledWeekdays"] as? [[String: Any]] {
                            // 旧形式からの復元を試行
                        }
                        
                        // unlockConditionTypeの復元（後方互換性）
                        var unlockTrigger: UnlockTrigger = .immediate
                        if let typeString = json["unlockConditionType"] as? String {
                            if typeString == "timeBased" {
                                unlockTrigger = .immediate
                            } else if typeString == "questionBased" {
                                let required = unlockRequiredQuestions > 0 ? unlockRequiredQuestions : 1
                                unlockTrigger = .questionCount(required: required)
                            }
                        } else {
                            // デフォルト: requiredQuestionsが1の場合はimmediate、それ以外はquestionCount
                            let required = unlockRequiredQuestions > 0 ? unlockRequiredQuestions : 1
                            unlockTrigger = required == 1 ? .immediate : .questionCount(required: required)
                        }
                        
                        // 新構造にマイグレーション
                        let downtime = DowntimeSettings(
                            startMinutes: startMinutes,
                            endMinutes: endMinutes,
                            enabledWeekdays: weekdays
                        )
                        let appLimit = AppLimitSettings(
                            dailyLimitMinutes: dailyLimitMinutes
                        )
                        return LockSlot(
                            downtime: downtime,
                            appLimit: appLimit,
                            unlockTrigger: unlockTrigger,
                            unlockDurationMinutes: unlockDurationMinutes > 0 ? unlockDurationMinutes : 10
                        )
                    }
                }
            }
            
            return LockSlot()  // デフォルト値
        }()


        let selection: FamilyActivitySelection = {
            guard let data = UserDefaults.standard.data(forKey: selectionKey),
                  let v = try? dec.decode(FamilyActivitySelection.self, from: data) else {
                return FamilyActivitySelection()
            }
            return v
        }()
        
        let downtimeSelection: FamilyActivitySelection = {
            guard let data = UserDefaults.standard.data(forKey: downtimeSelectionKey),
                  let v = try? dec.decode(FamilyActivitySelection.self, from: data) else {
                return FamilyActivitySelection()
            }
            return v
        }()
        
        let appLimitSelection: FamilyActivitySelection = {
            guard let data = UserDefaults.standard.data(forKey: appLimitSelectionKey),
                  let v = try? dec.decode(FamilyActivitySelection.self, from: data) else {
                return FamilyActivitySelection()
            }
            return v
        }()
        
        let unlockUntil: Date? = {
            guard let date = UserDefaults.standard.object(forKey: unlockUntilKey) as? Date else {
                return nil
            }
            // 過去の日付の場合はnilを返す
            return date > Date() ? date : nil
        }()

        return Loaded(pack: pack, slot: slot, selection: selection, downtimeSelection: downtimeSelection, appLimitSelection: appLimitSelection, unlockUntil: unlockUntil)
    }
}
