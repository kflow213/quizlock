import SwiftUI

struct QuizView: View {
    @EnvironmentObject var model: AppModel
    @State private var showNextQuestionDelay = false
    @State private var textAnswer: String = ""
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if let q = model.currentShuffled {
                    // 問題文
                    VStack(alignment: .leading, spacing: 12) {
                        Text("問題")
                            .font(.caption)
                            .foregroundStyle(.gray.opacity(0.7))
                        Text(q.questionText)
                            .font(.title3)
                            .fontWeight(.medium)
                            .foregroundStyle(.gray)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        if let hint = q.hint, !hint.isEmpty {
                            Divider()
                            HStack {
                                Image(systemName: "lightbulb")
                                    .font(.caption)
                                    .foregroundStyle(.gray.opacity(0.7))
                                Text("ヒント: \(hint)")
                                    .font(.caption)
                                    .foregroundStyle(.gray.opacity(0.7))
                            }
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    // 4択形式
                    if q.type == .multipleChoice, let choices = q.choices {
                        VStack(spacing: 12) {
                            ForEach(Array(choices.enumerated()), id: \.offset) { idx, choice in
                                Button {
                                    model.answer(choiceIndex: idx)
                                    // 不正解の場合は少し遅延して次の問題へ
                                    if model.lastAnswerWasCorrect == false {
                                        showNextQuestionDelay = true
                                        Task {
                                            try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5秒
                                            model.nextQuestion()
                                            showNextQuestionDelay = false
                                        }
                                    }
                                } label: {
                                    HStack {
                                        Text(choice)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .foregroundStyle(.gray)
                                    }
                                    .padding()
                                    .background(Color.gray.opacity(0.15))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                                .buttonStyle(.plain)
                                .disabled(model.lastAnswerWasCorrect != nil)
                            }
                        }
                    }
                    
                    // 記述式
                    if q.type == .textInput {
                        VStack(spacing: 12) {
                            TextField("答えを入力", text: $textAnswer)
                                .textFieldStyle(.plain)
                                .padding()
                                .background(Color.gray.opacity(0.15))
                                .foregroundStyle(.gray)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .focused($isTextFieldFocused)
                                .disabled(model.lastAnswerWasCorrect != nil)
                                .onSubmit {
                                    submitTextAnswer()
                                }
                            
                            Button {
                                submitTextAnswer()
                            } label: {
                                Text("回答")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.gray)
                                    .foregroundStyle(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .disabled(textAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.lastAnswerWasCorrect != nil)
                        }
                    }
                    
                    // スキップ機能（有効な場合のみ表示）
                    if model.slot.isSkipEnabled && model.lastAnswerWasCorrect == nil {
                        Button {
                            // スキップ機能：問題を解かずに解除
                            model.skipQuestion()
                        } label: {
                            HStack {
                                Image(systemName: "forward.fill")
                                Text("スキップ（問題を解かずに解除）")
                            }
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.orange.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }

                // フィードバック
                if let correct = model.lastAnswerWasCorrect {
                    if correct {
                        VStack(spacing: 8) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                switch model.slot.unlockTrigger {
                                case .immediate:
                                    Text("正解！\(model.slot.unlockDurationMinutes)分間解除します")
                                case .questionCount(let required):
                                    if model.correctCount >= required {
                                        Text("正解！\(model.slot.unlockDurationMinutes)分間解除します")
                                    } else {
                                        Text("正解！(\(model.correctCount)/\(required))")
                                    }
                                }
                            }
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.gray)
                            
                            if case .questionCount(let required) = model.slot.unlockTrigger,
                               model.correctCount < required {
                                Text("あと\(required - model.correctCount)問正解で解除")
                                    .font(.caption)
                                    .foregroundStyle(.gray.opacity(0.7))
                            }
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        if showNextQuestionDelay {
                            ProgressView("次の問題へ...")
                                .font(.subheadline)
                                .foregroundStyle(.gray)
                        } else {
                            HStack {
                                Image(systemName: "xmark.circle")
                                Text("不正解。次の問題へ")
                            }
                            .font(.subheadline)
                            .foregroundStyle(.gray.opacity(0.7))
                        }
                    }
                }
                } else {
                    ProgressView()
                        .tint(.gray)
                }
            }
            .padding()
        }
        .background(Color(white: 0.95))
        .navigationTitle("クイズ")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { 
            model.startQuiz()
            isTextFieldFocused = true
        }
    }
    
    private func submitTextAnswer() {
        guard !textAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        model.answerText(textAnswer)
        // 不正解の場合は少し遅延して次の問題へ
        if model.lastAnswerWasCorrect == false {
            showNextQuestionDelay = true
            textAnswer = ""
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5秒
                model.nextQuestion()
                showNextQuestionDelay = false
                isTextFieldFocused = true
            }
        } else if model.lastAnswerWasCorrect == true {
            textAnswer = ""
        }
    }
}
