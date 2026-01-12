import SwiftUI

// Identifiable payload for group editor sheet to avoid SwiftUI state race
// Using .sheet(item:) ensures the editor target is captured before the sheet is presented
// This prevents the "blank create group modal" race condition when editing immediately after navigation
enum GroupEditorTarget: Identifiable {
    case new
    case edit(groupId: UUID)
    
    var id: String {
        switch self {
        case .new:
            return "new"
        case .edit(let groupId):
            return "edit-\(groupId.uuidString)"
        }
    }
}

struct QuestionListView: View {
    @EnvironmentObject var model: AppModel
    @State private var showEditor = false
    @State private var editing: Question?
    @State private var groupEditorTarget: GroupEditorTarget?  // Use item-based sheet instead of boolean + editingGroup state
    @State private var searchText = ""
    @State private var showImportQuestion = false
    @State private var showGroupSelection = false
    @State private var groupToDelete: QuestionGroup?
    @State private var showDeleteGroupDialog = false
    
    var filteredGroups: [QuestionGroup] {
        let groups: [QuestionGroup]
        if searchText.isEmpty {
            groups = model.pack.groups
        } else {
            let searchLower = searchText.lowercased()
            groups = model.pack.groups.filter { group in
                let nameMatches = group.name.lowercased().contains(searchLower)
                let questions = groupQuestions(group)
                let questionMatches = questions.contains { question in
                    question.questionText.lowercased().contains(searchLower)
                }
                return nameMatches || questionMatches
            }
        }
        
        // 選択されたグループを一番上に表示
        let selectedGroups = groups.filter { model.pack.selectedGroupIds.contains($0.id) }
        let unselectedGroups = groups.filter { !model.pack.selectedGroupIds.contains($0.id) }
        return selectedGroups + unselectedGroups
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 検索バー
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.gray.opacity(0.6))
                TextField("検索", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(12)
            .background(Color(uiColor: .systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
            
            // グループリスト
            List {
                ForEach(filteredGroups) { group in
                    NavigationLink {
                        GroupDetailView(groupId: group.id)
                    } label: {
                        GroupRowContent(group: group, onEdit: {
                            // Use GroupEditorTarget to avoid state race
                            groupEditorTarget = .edit(groupId: group.id)
                        }, onShare: {
                            // 共有機能はGroupRowContent内で処理
                        }, onDelete: {
                            showDeleteGroupConfirmation(group: group)
                        })
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            showDeleteGroupConfirmation(group: group)
                        } label: {
                            Label("削除", systemImage: "trash")
                        }
                        
                        Button {
                            // グループをコピー
                            _ = model.copyGroup(groupId: group.id)
                        } label: {
                            Label("コピー", systemImage: "doc.on.doc")
                        }
                        
                        Button {
                            shareGroupDirectly(group: group)
                        } label: {
                            Label("共有", systemImage: "square.and.arrow.up")
                        }
                        
                        Button {
                            // Use GroupEditorTarget to avoid state race
                            groupEditorTarget = .edit(groupId: group.id)
                        } label: {
                            Label("編集", systemImage: "pencil")
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color(uiColor: .systemGroupedBackground))
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        }
        .navigationTitle("問題管理")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showImportQuestion = true
                } label: {
                    Image(systemName: "square.and.arrow.down")
                        .foregroundStyle(.gray)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 12) {
                Button {
                    showGroupSelection = true
                } label: {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("出題グループを選択")
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(uiColor: .systemBackground))
                    .foregroundStyle(.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                }
                
                Button {
                    // Use GroupEditorTarget to avoid state race
                    groupEditorTarget = .new
                } label: {
                    HStack {
                        Image(systemName: "folder.badge.plus")
                        Text("グループを追加")
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .shadow(color: Color.accentColor.opacity(0.3), radius: 4, x: 0, y: 2)
                }
            }
            .padding()
        }
        // Note: This sheet is for question editing, but it's not currently used
        // as question editing is now handled in GroupDetailView with EditorTarget
        // Keeping this for backward compatibility, but it should be removed if not needed
        .sheet(isPresented: $showEditor) {
            NavigationStack {
                QuestionEditorViewWithGroup(editing: editing, targetGroupId: nil)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("キャンセル") {
                                showEditor = false
                            }
                        }
                    }
            }
        }
        .sheet(item: $groupEditorTarget) { target in
            // Use item-based sheet to prevent state race where sheet is presented
            // before editingGroup is set, causing blank "create group" modal
            NavigationStack {
                switch target {
                case .new:
                    GroupEditorView(group: nil) { group in
                        model.addGroup(group)
                        groupEditorTarget = nil
                    }
                case .edit(let groupId):
                    // Fetch current group from model to ensure we have latest data
                    if let group = model.pack.groups.first(where: { $0.id == groupId }) {
                        GroupEditorView(group: group) { updatedGroup in
                            model.updateGroup(updatedGroup)
                            groupEditorTarget = nil
                        }
                    } else {
                        // Group not found - show error or dismiss
                        VStack {
                            Text("グループが見つかりません")
                                .foregroundStyle(.red)
                            Button("閉じる") {
                                groupEditorTarget = nil
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showImportQuestion) {
            ImportGroupView()
        }
        .sheet(isPresented: $showGroupSelection) {
            GroupSelectionView()
        }
        .confirmationDialog("グループを削除", isPresented: $showDeleteGroupDialog, presenting: groupToDelete) { group in
            Button("削除", role: .destructive) {
                // Deleting a group will also delete all questions inside it
                model.deleteGroup(group.id)
                groupToDelete = nil
            }
            Button("キャンセル", role: .cancel) {
                groupToDelete = nil
            }
        } message: { group in
            Text("「\(group.name)」を削除しますか？\n\nこのグループに属するすべての問題も削除されます。")
        }
    }
    
    private func showDeleteGroupConfirmation(group: QuestionGroup) {
        groupToDelete = group
        showDeleteGroupDialog = true
    }
    
    private func groupQuestions(_ group: QuestionGroup) -> [Question] {
        let questionIds = Set(group.questionIds)
        return model.pack.questions.filter { questionIds.contains($0.id) }
    }
}

struct GroupRow: View {
    let group: QuestionGroup
    let onTap: () -> Void
    let onEdit: () -> Void
    let onShare: () -> Void
    let onDelete: () -> Void
    @EnvironmentObject var model: AppModel
    @State private var showShare = false
    
    var isSelected: Bool {
        model.pack.selectedGroupIds.contains(group.id)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .foregroundStyle(isSelected ? .white : .blue)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(group.name)
                    .font(.headline)
                    .foregroundStyle(isSelected ? .white : .primary)
                
                Text("\(group.questionIds.count)問")
                    .font(.caption)
                    .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
            }
            
            Spacer()
        }
        .padding(16)
        .background(isSelected ? Color.blue : Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        .sheet(isPresented: $showShare) {
            ShareGroupView(group: group)
        }
    }
}

struct GroupRowContent: View {
    let group: QuestionGroup
    let onEdit: () -> Void
    let onShare: () -> Void
    let onDelete: () -> Void
    @EnvironmentObject var model: AppModel
    
    var isSelected: Bool {
        model.pack.selectedGroupIds.contains(group.id)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .foregroundStyle(isSelected ? .white : Color.accentColor)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(group.name)
                    .font(.headline)
                    .foregroundStyle(isSelected ? .white : .primary)
                
                Text("\(group.questionIds.count)問")
                    .font(.caption)
                    .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
            }
            
            Spacer()
            
            if isSelected {
                Text("選択中")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.2))
                    .clipShape(Capsule())
            }
        }
        .padding(16)
        .background(isSelected ? Color.accentColor : Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// Identifiable payload for move/copy sheet to avoid SwiftUI state race
// Using .sheet(item:) ensures the questionIds are captured before the sheet is presented
struct MoveCopyRequest: Identifiable {
    let id = UUID()
    let mode: GroupSelectionModalView.SelectionMode
    let sourceGroupId: UUID
    let questionIds: [UUID]  // Immutable snapshot captured at request creation
}

// Identifiable payload for editor sheet to avoid SwiftUI state race
// Using .sheet(item:) ensures the editor target is captured before the sheet is presented
// This prevents the "blank new question modal" race condition
enum EditorTarget: Identifiable {
    case new(groupId: UUID)
    case edit(questionId: UUID, groupId: UUID)
    
    var id: String {
        switch self {
        case .new(let groupId):
            return "new-\(groupId.uuidString)"
        case .edit(let questionId, let groupId):
            return "edit-\(questionId.uuidString)-\(groupId.uuidString)"
        }
    }
    
    var groupId: UUID {
        switch self {
        case .new(let groupId), .edit(_, let groupId):
            return groupId
        }
    }
}

struct GroupDetailView: View {
    let groupId: UUID
    @EnvironmentObject var model: AppModel
    @State private var editorTarget: EditorTarget?  // Use item-based sheet instead of boolean + editing state
    @State private var searchText = ""
    @State private var moveCopyRequest: MoveCopyRequest?  // Use item-based sheet instead of boolean
    @State private var isSelectionMode = false  // Multi-selection mode
    @State private var selectedQuestionIdsForBulk: Set<UUID> = []  // Selected questions in bulk mode
    
    var group: QuestionGroup? {
        model.pack.groups.first { $0.id == groupId }
    }
    
    var allQuestions: [Question] {
        guard let group = group else { return [] }
        let questionIds = Set(group.questionIds)
        return model.pack.questions.filter { questionIds.contains($0.id) }
    }
    
    var questions: [Question] {
        if searchText.isEmpty {
            return allQuestions
        }
        let searchLower = searchText.lowercased()
        return allQuestions.filter { question in
            question.questionText.lowercased().contains(searchLower) ||
            (question.hint?.lowercased().contains(searchLower) ?? false)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 検索バー
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.gray)
                TextField("検索", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
            .padding(.top, 8)
            
            List {
                if questions.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("問題がありません")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text("追加ボタンから問題を作成してください")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(questions) { question in
                        QuestionCard(
                            question: question,
                            groupId: groupId,
                            isSelectionMode: isSelectionMode,
                            isSelected: selectedQuestionIdsForBulk.contains(question.id)
                        ) {
                            if isSelectionMode {
                                // Toggle selection in bulk mode
                                if selectedQuestionIdsForBulk.contains(question.id) {
                                    selectedQuestionIdsForBulk.remove(question.id)
                                } else {
                                    selectedQuestionIdsForBulk.insert(question.id)
                                }
                            } else {
                                // Normal mode: edit - use EditorTarget to avoid state race
                                editorTarget = .edit(questionId: question.id, groupId: groupId)
                            }
                        } onMove: {
                            if !isSelectionMode {
                                // Create request with immutable snapshot to avoid state race
                                moveCopyRequest = MoveCopyRequest(
                                    mode: .move,
                                    sourceGroupId: groupId,
                                    questionIds: [question.id]
                                )
                            }
                        } onCopy: {
                            if !isSelectionMode {
                                // Create request with immutable snapshot to avoid state race
                                moveCopyRequest = MoveCopyRequest(
                                    mode: .copy,
                                    sourceGroupId: groupId,
                                    questionIds: [question.id]
                                )
                            }
                        } onDelete: {
                            if !isSelectionMode {
                                model.deleteQuestion(ids: [question.id])
                                if let group = group {
                                    model.removeQuestionFromGroup(questionId: question.id, groupId: group.id)
                                }
                            }
                        }
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .listRowBackground(Color.clear)
                        // Conditionally apply swipe actions only when NOT in selection mode
                        // In selection mode, swiping should do nothing (no swipe actions attached)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if !isSelectionMode {
                                Button(role: .destructive) {
                                    model.deleteQuestion(ids: [question.id])
                                    if let group = group {
                                        model.removeQuestionFromGroup(questionId: question.id, groupId: group.id)
                                    }
                                } label: {
                                    Label("削除", systemImage: "trash")
                                }
                                
                                Button {
                                    // Use EditorTarget to avoid state race
                                    editorTarget = .edit(questionId: question.id, groupId: groupId)
                                } label: {
                                    Label("編集", systemImage: "pencil")
                                }
                                
                                Button {
                                    // Create request with immutable snapshot to avoid state race
                                    moveCopyRequest = MoveCopyRequest(
                                        mode: .move,
                                        sourceGroupId: groupId,
                                        questionIds: [question.id]
                                    )
                                } label: {
                                    Label("移動", systemImage: "arrow.right")
                                }
                                
                                Button {
                                    // Create request with immutable snapshot to avoid state race
                                    moveCopyRequest = MoveCopyRequest(
                                        mode: .copy,
                                        sourceGroupId: groupId,
                                        questionIds: [question.id]
                                    )
                                } label: {
                                    Label("コピー", systemImage: "doc.on.doc")
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color(white: 0.98))
        }
        .navigationTitle(group?.name ?? "グループ")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if isSelectionMode {
                    Button("キャンセル") {
                        isSelectionMode = false
                        selectedQuestionIdsForBulk.removeAll()
                    }
                } else {
                    Button("選択") {
                        isSelectionMode = true
                    }
                }
            }
            
            ToolbarItem(placement: .topBarTrailing) {
                if isSelectionMode {
                    // Bulk action buttons
                    HStack(spacing: 12) {
                        Button {
                            // Bulk move - create request with immutable snapshot
                            moveCopyRequest = MoveCopyRequest(
                                mode: .move,
                                sourceGroupId: groupId,
                                questionIds: Array(selectedQuestionIdsForBulk)
                            )
                        } label: {
                            Image(systemName: "arrow.right")
                                .foregroundStyle(.blue)
                        }
                        .disabled(selectedQuestionIdsForBulk.isEmpty)
                        
                        Button {
                            // Bulk copy - create request with immutable snapshot
                            moveCopyRequest = MoveCopyRequest(
                                mode: .copy,
                                sourceGroupId: groupId,
                                questionIds: Array(selectedQuestionIdsForBulk)
                            )
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .foregroundStyle(.blue)
                        }
                        .disabled(selectedQuestionIdsForBulk.isEmpty)
                        
                        Button(role: .destructive) {
                            // Bulk delete
                            model.deleteQuestion(ids: Array(selectedQuestionIdsForBulk))
                            if let group = group {
                                for questionId in selectedQuestionIdsForBulk {
                                    model.removeQuestionFromGroup(questionId: questionId, groupId: group.id)
                                }
                            }
                            selectedQuestionIdsForBulk.removeAll()
                            isSelectionMode = false
                        } label: {
                            Image(systemName: "trash")
                        }
                        .disabled(selectedQuestionIdsForBulk.isEmpty)
                    }
                } else {
                    Button {
                        // Use EditorTarget to avoid state race
                        editorTarget = .new(groupId: groupId)
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(.gray)
                    }
                }
            }
        }
        .sheet(item: $editorTarget) { target in
            // Use item-based sheet to prevent state race where sheet is presented
            // before editing question is set, causing blank "new question" modal
            NavigationStack {
                switch target {
                case .new(let groupId):
                    QuestionEditorViewWithGroup(editing: nil, targetGroupId: groupId)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("キャンセル") {
                                    editorTarget = nil
                                }
                            }
                        }
                case .edit(let questionId, let groupId):
                    // Fetch current question from model to ensure we have latest data
                    if let question = model.pack.questions.first(where: { $0.id == questionId }) {
                        QuestionEditorView(editing: question)
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("キャンセル") {
                                        editorTarget = nil
                                    }
                                }
                            }
                    } else {
                        // Question not found - show error or dismiss
                        VStack {
                            Text("問題が見つかりません")
                                .foregroundStyle(.red)
                            Button("閉じる") {
                                editorTarget = nil
                            }
                        }
                    }
                }
            }
        }
        .sheet(item: $moveCopyRequest) { request in
            // Use item-based sheet to ensure questionIds are captured before presentation
            // This eliminates the SwiftUI state race where the sheet could be presented
            // before selectedQuestionIds is updated, resulting in empty questionIds
            GroupSelectionModalView(
                mode: request.mode,
                sourceGroupId: request.sourceGroupId,
                questionIds: request.questionIds  // Immutable snapshot from request
            )
            .environmentObject(model)
            .onDisappear {
                // Clear selection state after modal is dismissed
                if isSelectionMode {
                    selectedQuestionIdsForBulk.removeAll()
                    isSelectionMode = false
                }
            }
        }
    }
}


struct GroupHeader: View {
    let group: QuestionGroup
    @EnvironmentObject var model: AppModel
    
    var body: some View {
        HStack {
            Image(systemName: "folder.fill")
                .foregroundStyle(.gray)
            Text(group.name)
                .font(.headline)
            Spacer()
            Text("\(group.questionIds.count)問")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            if model.pack.selectedGroupIds.contains(group.id) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.gray)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // グループ選択をトグル
            model.toggleGroupSelection(group.id)
        }
    }
}

struct QuestionRow: View {
    let question: Question
    let onTap: () -> Void
    let onDelete: () -> Void
    @State private var showEdit = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(question.questionText.isEmpty ? "（無題）" : question.questionText)
                .font(.body)
                .lineLimit(2)
                .foregroundStyle(.gray)
            HStack(spacing: 8) {
                Text(question.type == .multipleChoice ? "4択" : "記述式")
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.2))
                    .foregroundStyle(.gray)
                    .clipShape(Capsule())
                
                if let hint = question.hint, !hint.isEmpty {
                    Image(systemName: "lightbulb")
                        .font(.caption)
                        .foregroundStyle(.gray.opacity(0.7))
                }
            }
        }
        .padding(.vertical, 8)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("削除", systemImage: "trash")
            }
            
            Button {
                showEdit = true
            } label: {
                Label("編集", systemImage: "pencil")
            }
        }
        .sheet(isPresented: $showEdit) {
            NavigationStack {
                QuestionEditorView(editing: question)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("キャンセル") {
                                showEdit = false
                            }
                        }
                    }
            }
        }
    }
}

struct ListQuestionRow: View {
    let question: Question
    let onTap: () -> Void
    let onShare: () -> Void
    let onDelete: () -> Void
    @State private var showShare = false
    @State private var showEdit = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(question.questionText.isEmpty ? "（無題）" : question.questionText)
                    .font(.body)
                    .lineLimit(2)
                    .foregroundStyle(.gray)
                    .multilineTextAlignment(.leading)
                
                HStack(spacing: 8) {
                    Text(question.type == .multipleChoice ? "4択" : "記述式")
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.gray.opacity(0.2))
                        .foregroundStyle(.gray)
                        .clipShape(Capsule())
                    
                    if let hint = question.hint, !hint.isEmpty {
                        Image(systemName: "lightbulb")
                            .font(.caption)
                            .foregroundStyle(.gray.opacity(0.7))
                    }
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 12)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("削除", systemImage: "trash")
            }
            
            Button {
                showEdit = true
            } label: {
                Label("編集", systemImage: "pencil")
            }
        }
        .sheet(isPresented: $showEdit) {
            NavigationStack {
                QuestionEditorView(editing: question)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("キャンセル") {
                                showEdit = false
                            }
                        }
                    }
            }
        }
    }
}

struct QuestionCard: View {
    let question: Question
    let groupId: UUID?
    let onTap: () -> Void
    let onMove: (() -> Void)?
    let onCopy: (() -> Void)?
    let onDelete: () -> Void
    let isSelectionMode: Bool  // Add parameter to conditionally disable swipe
    let isSelected: Bool  // Add parameter to show correct selection state
    
    init(
        question: Question,
        groupId: UUID? = nil,
        isSelectionMode: Bool = false,
        isSelected: Bool = false,
        onTap: @escaping () -> Void,
        onMove: (() -> Void)? = nil,
        onCopy: (() -> Void)? = nil,
        onDelete: @escaping () -> Void
    ) {
        self.question = question
        self.groupId = groupId
        self.isSelectionMode = isSelectionMode
        self.isSelected = isSelected
        self.onTap = onTap
        self.onMove = onMove
        self.onCopy = onCopy
        self.onDelete = onDelete
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(question.questionText.isEmpty ? "（無題）" : question.questionText)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            
            HStack(spacing: 8) {
                Text(question.type == .multipleChoice ? "4択" : "記述式")
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .foregroundStyle(.blue)
                    .clipShape(Capsule())
                
                if let hint = question.hint, !hint.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "lightbulb.fill")
                            .font(.caption2)
                        Text("ヒント")
                            .font(.caption2)
                    }
                    .foregroundStyle(.orange)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        .contentShape(Rectangle())  // Make entire card tappable
        .onTapGesture {
            onTap()  // Call onTap to toggle selection or edit
        }
        .overlay(
            // Selection indicator overlay - must not block taps
            // Show checkmark only when actually selected, circle when in selection mode but not selected
            Group {
                if isSelectionMode {
                    HStack {
                        Spacer()
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isSelected ? .blue : .gray)
                            .font(.title3)
                            .padding(.trailing, 16)
                    }
                }
            }
            .allowsHitTesting(false)  // Overlay does not block taps
        )
    }
}

struct GroupEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let group: QuestionGroup?
    let onSave: (QuestionGroup) -> Void
    
    @State private var groupName: String = ""
    
    var body: some View {
        Form {
            Section {
                TextField("グループ名", text: $groupName)
            } header: {
                Text("グループ名")
            }
            
            Section {
                Button {
                    let newGroup = QuestionGroup(
                        id: group?.id ?? UUID(),
                        name: groupName,
                        questionIds: group?.questionIds ?? [],
                        createdAt: group?.createdAt ?? Date()
                    )
                    onSave(newGroup)
                } label: {
                    Text("保存")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.gray)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .navigationTitle(group == nil ? "グループ作成" : "グループ編集")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            groupName = group?.name ?? ""
        }
    }
}

extension QuestionListView {
    private func createGroupShareData(group: QuestionGroup) -> URL? {
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
    
    func shareGroupDirectly(group: QuestionGroup) {
        let groupQuestions = model.pack.questions.filter { group.questionIds.contains($0.id) }
        let shareData = ShareableGroup(
            groupName: group.name,
            questions: groupQuestions
        )
        
        guard let jsonData = try? JSONEncoder().encode(shareData),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return
        }
        
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(group.name).quizlock")
        
        try? jsonString.write(to: tempURL, atomically: true, encoding: .utf8)
        
        let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            rootViewController.present(activityVC, animated: true)
        }
    }
}
