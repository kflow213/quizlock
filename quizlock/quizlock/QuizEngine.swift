import Foundation

/// クイズ問題（4択または記述式）
struct ShuffledQuestion {
    let questionId: UUID
    let questionText: String
    let type: QuestionType
    let hint: String?  // ヒント
    
    // 4択形式用
    let choices: [String]?          // シャッフル済み
    let correctShuffledIndex: Int?  // 0...3（シャッフル後の正解インデックス）
    
    // 記述式用
    let correctAnswer: String?     // 正解の答え（大文字小文字・前後の空白は無視して判定）
}

/// クイズエンジン（問題の準備処理）
struct QuizEngine {
    /// 問題を準備（4択の場合はシャッフル、記述式の場合はそのまま）
    /// - Parameter q: 元の問題（4択または記述式）
    /// - Returns: 準備済み問題
    static func prepareQuestion(from q: Question) -> ShuffledQuestion {
        switch q.type {
        case .multipleChoice:
            return prepareMultipleChoice(from: q)
        case .textInput:
            return prepareTextInput(from: q)
        }
    }
    
    /// 4択問題をシャッフル
    private static func prepareMultipleChoice(from q: Question) -> ShuffledQuestion {
        guard let choices = q.choices, choices.count == 4,
              let correctIndex = q.correctIndex, (0..<4).contains(correctIndex) else {
            fatalError("Invalid multiple choice question")
        }
        
        let paired = choices.enumerated().map { (idx, text) in (text, idx) }
        let shuffled = paired.shuffled()
        
        let shuffledChoices = shuffled.map { $0.0 }
        let correctShuffledIndex = shuffled.firstIndex(where: { $0.1 == correctIndex }) ?? 0
        
        return ShuffledQuestion(
            questionId: q.id,
            questionText: q.questionText,
            type: .multipleChoice,
            hint: q.hint,
            choices: shuffledChoices,
            correctShuffledIndex: correctShuffledIndex,
            correctAnswer: nil
        )
    }
    
    /// 記述式問題を準備
    private static func prepareTextInput(from q: Question) -> ShuffledQuestion {
        guard let correctAnswer = q.correctAnswer else {
            fatalError("Invalid text input question")
        }
        
        return ShuffledQuestion(
            questionId: q.id,
            questionText: q.questionText,
            type: .textInput,
            hint: q.hint,
            choices: nil,
            correctShuffledIndex: nil,
            correctAnswer: correctAnswer
        )
    }
    
    /// 記述式の回答が正解かどうかを判定（大文字小文字・前後の空白を無視）
    static func isTextAnswerCorrect(userAnswer: String, correctAnswer: String) -> Bool {
        let normalizedUser = userAnswer.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedCorrect = correctAnswer.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalizedUser == normalizedCorrect
    }
}
