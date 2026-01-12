import SwiftUI

struct QuestionEditorView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let editing: Question?
    /// Called when a new question is saved (not called for edits)
    var onSaved: ((UUID) -> Void)? = nil

    @State private var questionType: QuestionType = .multipleChoice
    @State private var questionText: String = ""
    @State private var hint: String = ""
    @State private var choices: [String] = ["", "", "", ""]
    @State private var correctIndex: Int = 0
    @State private var correctAnswer: String = ""
    @State private var errorText: String?

    var body: some View {
        Form {
            Section {
                Picker("形式", selection: $questionType) {
                    Text("4択").tag(QuestionType.multipleChoice)
                    Text("記述式").tag(QuestionType.textInput)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("問題形式")
            }
            
            Section {
                TextField("問題文", text: $questionText, axis: .vertical)
                    .lineLimit(2...6)
            } header: {
                Text("問題")
            }
            
            Section {
                TextField("ヒント（任意）", text: $hint, axis: .vertical)
                    .lineLimit(2...4)
            } header: {
                Text("ヒント")
            } footer: {
                Text("問題を解く際のヒントを入力できます（任意）")
            }

            if questionType == .multipleChoice {
                Section {
                    ForEach(0..<4, id: \.self) { i in
                        HStack {
                            Text("\(i+1).")
                                .frame(width: 24, alignment: .leading)
                                .foregroundStyle(.secondary)
                            TextField("選択肢", text: Binding(
                                get: { choices[i] },
                                set: { choices[i] = $0 }
                            ))
                        }
                    }
                } header: {
                    Text("選択肢（4つ）")
                }

                Section {
                    Picker("正解", selection: $correctIndex) {
                        ForEach(0..<4, id: \.self) { Text("\($0+1)") }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("正解")
                }
            } else {
                Section {
                    TextField("正解を入力", text: $correctAnswer)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("正解の答え")
                } footer: {
                    Text("※ 大文字小文字・前後の空白は無視して判定されます")
                }
            }

            if let err = errorText {
                Section {
                    Text(err)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button { save() } label: {
                    Text(editing == nil ? "追加" : "保存")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.gray)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)

                Button(role: .cancel) { dismiss() } label: {
                    Text("キャンセル")
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(white: 0.95))
        .navigationTitle(editing == nil ? "問題作成" : "問題編集")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let q = editing {
                questionType = q.type
                questionText = q.questionText
                hint = q.hint ?? ""
                if q.type == .multipleChoice {
                    choices = q.choices ?? ["", "", "", ""]
                    correctIndex = q.correctIndex ?? 0
                } else {
                    correctAnswer = q.correctAnswer ?? ""
                }
            }
        }
    }

    private func save() {
        errorText = nil
        let trimmedQ = questionText.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedQ.isEmpty {
            errorText = "問題文を入力してください。"
            return
        }
        
        if questionType == .multipleChoice {
            if choices.count != 4 || choices.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                errorText = "選択肢は4つすべて入力してください。"
                return
            }
            guard (0..<4).contains(correctIndex) else {
                errorText = "正解を選んでください。"
                return
            }
            
            if var q = editing {
                q.type = .multipleChoice
                q.questionText = trimmedQ
                q.hint = hint.isEmpty ? nil : hint
                q.choices = choices
                q.correctIndex = correctIndex
                q.correctAnswer = nil
                model.updateQuestion(q)
            } else {
                let newQuestion = Question(questionText: trimmedQ, choices: choices, correctIndex: correctIndex, hint: hint.isEmpty ? nil : hint)
                model.addQuestion(newQuestion)
                // Call onSaved callback only for newly created questions
                onSaved?(newQuestion.id)
            }
        } else {
            let trimmedAnswer = correctAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedAnswer.isEmpty {
                errorText = "正解の答えを入力してください。"
                return
            }
            
            if var q = editing {
                q.type = .textInput
                q.questionText = trimmedQ
                q.hint = hint.isEmpty ? nil : hint
                q.choices = nil
                q.correctIndex = nil
                q.correctAnswer = trimmedAnswer
                model.updateQuestion(q)
            } else {
                let newQuestion = Question(questionText: trimmedQ, correctAnswer: trimmedAnswer, hint: hint.isEmpty ? nil : hint)
                model.addQuestion(newQuestion)
                // Call onSaved callback only for newly created questions
                onSaved?(newQuestion.id)
            }
        }
        dismiss()
    }
}
