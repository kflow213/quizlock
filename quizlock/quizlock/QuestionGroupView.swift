import SwiftUI

struct QuestionGroupView: View {
    @EnvironmentObject var model: AppModel
    @State private var showGroupEditor = false
    @State private var editingGroup: QuestionGroup?
    @State private var showGroupDetail: QuestionGroup?
    @State private var showImport = false

    var body: some View {
        List {
            if model.pack.groups.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "folder")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("グループがありません")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("追加ボタンからグループを作成してください")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .listRowSeparator(.hidden)
            } else {
                ForEach(model.pack.groups) { group in
                    Button {
                        showGroupDetail = group
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(group.name)
                                    .font(.body)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.gray)
                                
                                HStack(spacing: 12) {
                                    Text("\(group.questionIds.count)問")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    
                                    if model.isGroupSelected(group.id) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "checkmark.circle.fill")
                                            Text("選択中")
                                        }
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                    }
                                }
                            }
                            
                            Spacer()
                            
                            Button {
                                model.toggleGroupSelection(group.id)
                            } label: {
                                Image(systemName: model.isGroupSelected(group.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(model.isGroupSelected(group.id) ? .green : .gray)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            showGroupDetail = group
                        } label: {
                            Label("共有", systemImage: "square.and.arrow.up")
                        }
                        
                        Button(role: .destructive) {
                            model.deleteGroup(group.id)
                        } label: {
                            Label("削除", systemImage: "trash")
                        }
                        
                        Button {
                            editingGroup = group
                            showGroupEditor = true
                        } label: {
                            Label("編集", systemImage: "pencil")
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(white: 0.95))
        .navigationTitle("グループ管理")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack {
                    Button {
                        showImport = true
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                            .foregroundStyle(.black)
                    }
                    
                    Button {
                        editingGroup = nil
                        showGroupEditor = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(.black)
                    }
                }
            }
        }
        .sheet(isPresented: $showGroupEditor) {
            QuestionGroupEditorView(group: editingGroup)
        }
        .sheet(item: $showGroupDetail) { group in
            QuestionGroupDetailView(group: group)
        }
        .sheet(isPresented: $showImport) {
            ImportGroupView()
        }
    }
}

struct QuestionGroupEditorView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    
    let group: QuestionGroup?
    @State private var name: String = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("グループ名", text: $name)
                } header: {
                    Text("グループ名")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(white: 0.95))
            .navigationTitle(group == nil ? "グループ作成" : "グループ編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        save()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                if let group = group {
                    name = group.name
                }
            }
        }
    }
    
    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        
        if let group = group {
            var updated = group
            updated.name = trimmedName
            model.updateGroup(updated)
        } else {
            let newGroup = QuestionGroup(name: trimmedName)
            model.addGroup(newGroup)
        }
        dismiss()
    }
}

struct QuestionGroupDetailView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    
    let group: QuestionGroup
    @State private var showQuestionSelector = false
    @State private var showShare = false
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("\(group.questionIds.count)問")
                        .font(.headline)
                } header: {
                    Text("問題数")
                }
                
                Section {
                    let groupQuestions = model.pack.questions.filter { group.questionIds.contains($0.id) }
                    if groupQuestions.isEmpty {
                        Text("問題がありません")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(groupQuestions) { question in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(question.questionText)
                                    .font(.body)
                                Text(question.type == .multipleChoice ? "4択" : "記述式")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .onDelete { offsets in
                            let questions = groupQuestions
                            for offset in offsets {
                                model.removeQuestionFromGroup(questionId: questions[offset].id, groupId: group.id)
                            }
                        }
                    }
                } header: {
                    Text("問題一覧")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(white: 0.95))
            .navigationTitle(group.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack {
                        Button {
                            showShare = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundStyle(.gray)
                        }
                        
                        Button {
                            showQuestionSelector = true
                        } label: {
                            Image(systemName: "plus")
                                .foregroundStyle(.gray)
                        }
                    }
                }
            }
            .sheet(isPresented: $showQuestionSelector) {
                QuestionSelectorView(groupId: group.id)
            }
            .sheet(isPresented: $showShare) {
                ShareGroupView(group: group)
            }
        }
    }
}

struct QuestionSelectorView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    
    let groupId: UUID
    @State private var selectedQuestionIds: Set<UUID> = []
    
    var body: some View {
        NavigationStack {
            List {
                let group = model.pack.groups.first { $0.id == groupId }
                let availableQuestions = model.pack.questions.filter { question in
                    !(group?.questionIds.contains(question.id) ?? false)
                }
                
                if availableQuestions.isEmpty {
                    Text("追加できる問題がありません")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(availableQuestions) { question in
                        Button {
                            if selectedQuestionIds.contains(question.id) {
                                selectedQuestionIds.remove(question.id)
                            } else {
                                selectedQuestionIds.insert(question.id)
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(question.questionText)
                                        .font(.body)
                                        .foregroundStyle(.gray)
                                    Text(question.type == .multipleChoice ? "4択" : "記述式")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if selectedQuestionIds.contains(question.id) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(white: 0.95))
            .navigationTitle("問題を追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("追加") {
                        for questionId in selectedQuestionIds {
                            model.addQuestionToGroup(questionId: questionId, groupId: groupId)
                        }
                        dismiss()
                    }
                    .disabled(selectedQuestionIds.isEmpty)
                }
            }
        }
    }
}
