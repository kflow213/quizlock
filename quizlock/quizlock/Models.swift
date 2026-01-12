import Foundation

/// 問題の形式
enum QuestionType: String, Codable {
    case multipleChoice  // 4択形式
    case textInput       // 記述式
}

/// クイズ問題（4択形式または記述式）
/// - Note: v1.0では自作問題のみ対応、問題データはローカル保存
struct Question: Identifiable, Codable, Equatable {
    let id: UUID
    var type: QuestionType
    var questionText: String
    var hint: String?  // ヒント（4択・記述式両方で使用可能）
    
    // 4択形式用
    var choices: [String]?      // 4択の場合のみ（必ず4つ）
    var correctIndex: Int?      // 4択の場合のみ（0...3）
    
    // 記述式用
    var correctAnswer: String?  // 記述式の場合のみ（大文字小文字・前後の空白は無視して判定）

    // 4択形式のイニシャライザ
    init(
        id: UUID = UUID(),
        questionText: String,
        choices: [String],
        correctIndex: Int,
        hint: String? = nil
    ) {
        self.id = id
        self.type = .multipleChoice
        self.questionText = questionText
        self.choices = choices
        self.correctIndex = correctIndex
        self.correctAnswer = nil
        self.hint = hint
    }
    
    // 記述式のイニシャライザ
    init(
        id: UUID = UUID(),
        questionText: String,
        correctAnswer: String,
        hint: String? = nil
    ) {
        self.id = id
        self.type = .textInput
        self.questionText = questionText
        self.choices = nil
        self.correctIndex = nil
        self.correctAnswer = correctAnswer
        self.hint = hint
    }
}

/// 問題グループ
struct QuestionGroup: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var questionIds: [UUID]  // このグループに含まれる問題のID
    var createdAt: Date
    
    init(id: UUID = UUID(), name: String, questionIds: [UUID] = [], createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.questionIds = questionIds
        self.createdAt = createdAt
    }
}

/// 問題パック（UUID + schemaVersion による管理）
/// - Note: 問題データはローカル保存、追加/編集/削除に対応
struct QuestionPack: Codable, Equatable {
    let schemaVersion: Int     // v2.0: 2 (グループ機能追加)
    var questions: [Question]
    var groups: [QuestionGroup]  // 問題グループ
    var selectedGroupIds: [UUID]  // 選択されているグループID（空の場合は全問題）
    var updatedAt: Date

    init(schemaVersion: Int = 2, questions: [Question] = [], groups: [QuestionGroup] = [], selectedGroupIds: [UUID] = [], updatedAt: Date = Date()) {
        self.schemaVersion = schemaVersion
        self.questions = questions
        self.groups = groups
        self.selectedGroupIds = selectedGroupIds
        self.updatedAt = updatedAt
    }

    static let defaultPack: QuestionPack = {
        // 初期状態：グループと問題を一つずつ用意
        let defaultQuestion = Question(
            questionText: "サンプル問題",
            choices: ["選択肢1", "選択肢2", "選択肢3", "選択肢4"],
            correctIndex: 0,
            hint: "これはサンプル問題です"
        )
        let defaultGroup = QuestionGroup(
            name: "サンプルグループ",
            questionIds: [defaultQuestion.id],
            createdAt: Date()
        )
        return QuestionPack(
            schemaVersion: 2,
            questions: [defaultQuestion],
            groups: [defaultGroup],
            selectedGroupIds: [defaultGroup.id],
            updatedAt: Date()
        )
    }()
    
    /// 選択されたグループの問題のみを取得
    func selectedQuestions() -> [Question] {
        if selectedGroupIds.isEmpty {
            // グループが選択されていない場合は全問題
            return questions
        }
        
        // Setを使って効率化
        let selectedGroupIdSet = Set(selectedGroupIds)
        let selectedQuestionIdSet = Set(
            groups
                .filter { selectedGroupIdSet.contains($0.id) }
                .flatMap { $0.questionIds }
        )
        
        return questions.filter { selectedQuestionIdSet.contains($0.id) }
    }

    /// QuizEngine方式で問題を準備（選択されたグループの問題のみ）
    func randomShuffled() -> ShuffledQuestion? {
        let availableQuestions = selectedQuestions()
        guard let q = availableQuestions.randomElement() else { return nil }
        return QuizEngine.prepareQuestion(from: q)
    }
}

/// 時間制限タイプ
enum TimeRestrictionType: String, Codable {
    case downtime      // 休止時間（指定時間帯に完全ブロック）
    case appLimit      // 使用時間制限（1日の使用時間を制限）- 有料機能
}

/// 曜日（1=日曜日、7=土曜日）
enum Weekday: Int, Codable, CaseIterable {
    case sunday = 1
    case monday = 2
    case tuesday = 3
    case wednesday = 4
    case thursday = 5
    case friday = 6
    case saturday = 7
    
    var displayName: String {
        switch self {
        case .sunday: return "日"
        case .monday: return "月"
        case .tuesday: return "火"
        case .wednesday: return "水"
        case .thursday: return "木"
        case .friday: return "金"
        case .saturday: return "土"
        }
    }
}

/// アンロックトリガー（何がアンロックを開始するか）
enum UnlockTrigger: Codable, Equatable {
    case immediate  // 即座にアンロック（将来の使用のため）
    case questionCount(required: Int)  // 指定問題数正解するとアンロック
    
    // 後方互換性のためのCodable実装
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
            // 後方互換性: 古いUnlockConditionTypeを変換
            if type == "timeBased" {
                self = .immediate
            } else if type == "questionBased" {
                let required = try? container.decode(Int.self, forKey: .required) ?? 1
                self = .questionCount(required: required ?? 1)
            } else {
                self = .immediate  // デフォルト
            }
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
    
    /// 必要な問題数を取得（questionCountの場合のみ）
    var requiredQuestionCount: Int? {
        switch self {
        case .immediate:
            return nil
        case .questionCount(let required):
            return required
        }
    }
}

// 後方互換性のための型エイリアス（段階的な移行のため）
typealias UnlockConditionType = UnlockTrigger

// 後方互換性のための拡張（古いコードがrawValueを使用している場合）
extension UnlockTrigger {
    /// 後方互換性のためのrawValue（古いコードとの互換性）
    var rawValue: String {
        switch self {
        case .immediate:
            return "timeBased"  // 古いコードとの互換性
        case .questionCount:
            return "questionBased"  // 古いコードとの互換性
        }
    }
    
    /// 後方互換性のためのイニシャライザ（rawValueから）
    init?(rawValue: String) {
        switch rawValue {
        case "timeBased", "immediate":
            self = .immediate
        case "questionBased":
            // デフォルト値として1を使用（後方互換性のため）
            self = .questionCount(required: 1)
        default:
            return nil
        }
    }
}

/// 休止時間設定（完全に独立）
struct DowntimeSettings: Codable, Equatable {
    var startMinutes: Int = 0  // 0..1439（分単位）
    var endMinutes: Int = 1    // 0..1439（分単位、start==endのみ不可）
    var enabledWeekdays: Set<Weekday> = Set(Weekday.allCases)  // 適用する曜日
    
    init(
        startMinutes: Int = 0,
        endMinutes: Int = 1,
        enabledWeekdays: Set<Weekday> = Set(Weekday.allCases)
    ) {
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
        self.enabledWeekdays = enabledWeekdays
    }
}

/// 使用時間制限設定（完全に独立）
struct AppLimitSettings: Codable, Equatable {
    var dailyLimitMinutes: Int?  // 1日の使用時間制限（分単位、nilの場合は無制限）
    
    init(dailyLimitMinutes: Int? = nil) {
        self.dailyLimitMinutes = dailyLimitMinutes
    }
}

/// ロック時間枠（休止時間・使用時間制限を完全に分離）
struct LockSlot: Codable, Equatable {
    // 休止時間設定（完全に独立）
    var downtime: DowntimeSettings = DowntimeSettings()
    
    // 使用時間制限設定（完全に独立）
    var appLimit: AppLimitSettings = AppLimitSettings()
    
    // 解除条件設定（両方の機能で共有）
    // アンロックトリガー：何がアンロックを開始するか
    var unlockTrigger: UnlockTrigger = .immediate
    // アンロック期間：アンロックが有効な時間（分単位、常に存在）
    var unlockDurationMinutes: Int = 10
    // 後方互換性のためのcomputed properties
    var unlockConditionType: UnlockConditionType {
        get { unlockTrigger }
        set { unlockTrigger = newValue }
    }
    var unlockRequiredQuestions: Int {
        get { unlockTrigger.requiredQuestionCount ?? 1 }
        set {
            if newValue > 0 {
                unlockTrigger = .questionCount(required: newValue)
            } else {
                unlockTrigger = .immediate
            }
        }
    }
    var isSkipEnabled: Bool = false  // スキップ機能の有効/無効（問題がわからないときに問題を解かずに解除できる）
    
    // 後方互換性のためのcomputed properties（既存コードとの互換性）
    var restrictionType: TimeRestrictionType {
        get { .downtime }  // デフォルトはdowntime（後方互換性のため）
        set { }  // 設定は無視（分離された設定を使用）
    }
    
    var startMinutes: Int {
        get { downtime.startMinutes }
        set { downtime.startMinutes = newValue }
    }
    
    var endMinutes: Int {
        get { downtime.endMinutes }
        set { downtime.endMinutes = newValue }
    }
    
    var dailyLimitMinutes: Int? {
        get { appLimit.dailyLimitMinutes }
        set { appLimit.dailyLimitMinutes = newValue }
    }
    
    var enabledWeekdays: Set<Weekday> {
        get { downtime.enabledWeekdays }
        set { downtime.enabledWeekdays = newValue }
    }

    init(
        downtime: DowntimeSettings = DowntimeSettings(),
        appLimit: AppLimitSettings = AppLimitSettings(),
        unlockTrigger: UnlockTrigger = .immediate,
        unlockDurationMinutes: Int = 10,
        isSkipEnabled: Bool = false
    ) {
        self.downtime = downtime
        self.appLimit = appLimit
        self.unlockTrigger = unlockTrigger
        self.unlockDurationMinutes = unlockDurationMinutes
        self.isSkipEnabled = isSkipEnabled
    }
    
    // 後方互換性のためのイニシャライザ
    init(
        downtime: DowntimeSettings,
        appLimit: AppLimitSettings,
        unlockConditionType: UnlockConditionType,
        unlockDurationMinutes: Int,
        unlockRequiredQuestions: Int,
        isSkipEnabled: Bool
    ) {
        self.downtime = downtime
        self.appLimit = appLimit
        self.unlockTrigger = unlockConditionType
        self.unlockDurationMinutes = unlockDurationMinutes
        self.isSkipEnabled = isSkipEnabled
        // unlockRequiredQuestionsはunlockTriggerから取得されるため、ここでは設定しない
    }
}
