import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ShareView: UIViewControllerRepresentable {
    let items: [Any]
    let applicationActivities: [UIActivity]? = nil
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: items,
            applicationActivities: applicationActivities
        )
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct ShareGroupView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let group: QuestionGroup
    
    var body: some View {
        if let shareData = createShareData() {
            ShareView(items: [shareData])
        } else {
            VStack {
                Text("共有データの作成に失敗しました")
                    .foregroundStyle(.red)
            }
        }
    }
    
    private func createShareData() -> URL? {
        let groupQuestions = model.pack.questions.filter { group.questionIds.contains($0.id) }
        let shareData = ShareableGroup(
            groupName: group.name,
            questions: groupQuestions
        )
        
        guard let jsonData = try? JSONEncoder().encode(shareData),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return nil
        }
        
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(group.name).quizlock")
        
        try? jsonString.write(to: tempURL, atomically: true, encoding: .utf8)
        return tempURL
    }
}

struct ShareableGroup: Codable {
    let groupName: String
    let questions: [Question]
    let version: String = "1.0"
}

struct ImportGroupView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var showDocumentPicker = false
    @State private var importError: String?
    @State private var showImportError = false
    @State private var isImporting = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 64))
                    .foregroundStyle(.secondary)
                
                Text("グループをインポート")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("共有された.quizlockファイルを選択してください\n（グループ単位でのみインポート可能）")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Button {
                    showDocumentPicker = true
                } label: {
                    HStack {
                        if isImporting {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Image(systemName: "folder")
                        }
                        Text(isImporting ? "インポート中..." : "ファイルを選択")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isImporting ? Color.gray : Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal)
                .disabled(isImporting)
            }
            .padding()
            .navigationTitle("インポート")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
            }
            .sheet(isPresented: $showDocumentPicker) {
                DocumentPicker { url in
                    loadGroup(from: url)
                }
            }
            .alert("インポートエラー", isPresented: $showImportError) {
                Button("OK") { }
            } message: {
                Text(importError ?? "不明なエラーが発生しました")
            }
        }
    }
    
    private func loadGroup(from url: URL) {
        #if DEBUG
        print("📥 picked url: \(url)")
        #endif
        isImporting = true
        
        // Start accessing security-scoped resource
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        // Copy file to temporary location for safe access
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("quizlock")
        
        do {
            // Remove existing temp file if any
            if FileManager.default.fileExists(atPath: tempURL.path) {
                try FileManager.default.removeItem(at: tempURL)
            }
            
            // Copy file to temp location
            try FileManager.default.copyItem(at: url, to: tempURL)
            #if DEBUG
            print("📋 copied file to temp: \(tempURL)")
            #endif
            
            // Read data from temp file
            guard let data = try? Data(contentsOf: tempURL) else {
                #if DEBUG
                print("❌ failed to read data from temp file")
                #endif
                DispatchQueue.main.async {
                    self.isImporting = false
                    self.importError = "ファイルの読み込みに失敗しました"
                    self.showImportError = true
                }
                return
            }
            #if DEBUG
            print("📊 read data bytes: \(data.count)")
            #endif
            
            // Decode JSON
            guard let shareData = try? JSONDecoder().decode(ShareableGroup.self, from: data) else {
                #if DEBUG
                print("❌ failed to decode JSON")
                #endif
                DispatchQueue.main.async {
                    self.isImporting = false
                    self.importError = "ファイルの形式が正しくありません"
                    self.showImportError = true
                }
                return
            }
            #if DEBUG
            print("✅ decoded group name: \(shareData.groupName), questions: \(shareData.questions.count)")
            #endif
            
            // Validate imported data
            guard !shareData.groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                DispatchQueue.main.async {
                    self.isImporting = false
                    self.importError = "グループ名が無効です"
                    self.showImportError = true
                }
                return
            }
            
            guard !shareData.questions.isEmpty else {
                DispatchQueue.main.async {
                    self.isImporting = false
                    self.importError = "問題が含まれていません"
                    self.showImportError = true
                }
                return
            }
            
            // Perform import immediately on main thread
            DispatchQueue.main.async {
                #if DEBUG
                print("🔄 adding group to model...")
                #endif
                
                // Import always creates a new group (GROUP-ONLY import)
                // Create new Question instances with new UUIDs
                var importedQuestionIds: [UUID] = []
                for question in shareData.questions {
                    var newQuestion: Question
                    if question.type == .multipleChoice {
                        newQuestion = Question(
                            questionText: question.questionText,
                            choices: question.choices ?? [],
                            correctIndex: question.correctIndex ?? 0,
                            hint: question.hint
                        )
                    } else {
                        newQuestion = Question(
                            questionText: question.questionText,
                            correctAnswer: question.correctAnswer ?? "",
                            hint: question.hint
                        )
                    }
                    self.model.addQuestion(newQuestion)
                    importedQuestionIds.append(newQuestion.id)
                }
                
                // Always create a new group with imported questions
                let newGroup = QuestionGroup(name: shareData.groupName, questionIds: importedQuestionIds)
                self.model.addGroup(newGroup)
                
                #if DEBUG
                print("✅ import complete, dismissing view...")
                
                // Verify the group was added
                if self.model.pack.groups.contains(where: { $0.id == newGroup.id }) {
                    print("✅ group verified in model")
                } else {
                    print("⚠️ warning: group not found in model after add")
                }
                #endif
                
                // Dismiss immediately after successful import
                self.isImporting = false
                self.dismiss()
            }
            
            // Clean up temp file
            try? FileManager.default.removeItem(at: tempURL)
        } catch {
            #if DEBUG
            print("❌ error during file access: \(error)")
            #endif
            DispatchQueue.main.async {
                self.isImporting = false
                self.importError = "ファイルへのアクセスに失敗しました: \(error.localizedDescription)"
                self.showImportError = true
            }
        }
    }
}

struct DocumentPicker: UIViewControllerRepresentable {
    let onDocumentPicked: (URL) -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.data])
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onDocumentPicked: onDocumentPicked)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onDocumentPicked: (URL) -> Void
        
        init(onDocumentPicked: @escaping (URL) -> Void) {
            self.onDocumentPicked = onDocumentPicked
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            #if DEBUG
            print("📂 documentPicker didPickDocumentsAt: \(urls.count) files")
            #endif
            guard let url = urls.first else {
                #if DEBUG
                print("⚠️ no URL provided")
                #endif
                return
            }
            
            // Ensure callback is called on main thread
            DispatchQueue.main.async {
                #if DEBUG
                print("📤 calling onDocumentPicked with url: \(url)")
                #endif
                self.onDocumentPicked(url)
            }
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            #if DEBUG
            print("❌ documentPicker was cancelled")
            #endif
        }
    }
}
