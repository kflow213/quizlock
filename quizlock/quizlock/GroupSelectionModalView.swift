import SwiftUI

/// グループ選択モーダル（問題の移動/コピー用）
struct GroupSelectionModalView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    
    let mode: SelectionMode
    let sourceGroupId: UUID?
    let questionIds: [UUID]  // Immutable snapshot passed from parent
    
    @State private var selectedGroupIds: Set<UUID> = []
    @State private var newGroupName: String = ""
    @State private var showNewGroupField = false
    @State private var actionError: String?
    @State private var showActionError = false
    
    enum SelectionMode {
        case move    // 移動（1つのグループのみ選択可能）
        case copy    // コピー（複数グループ選択可能）
    }
    
    var body: some View {
        NavigationStack {
            List {
                // 新規グループ作成オプション
                Section {
                    Toggle("新規グループを作成", isOn: $showNewGroupField)
                    
                    if showNewGroupField {
                        TextField("グループ名", text: $newGroupName)
                            .textFieldStyle(.roundedBorder)
                    }
                } header: {
                    Text("新規グループ")
                }
                
                // 既存のグループ一覧
                Section {
                    ForEach(model.pack.groups) { group in
                        // 移動の場合は元のグループを除外
                        if mode == .move, let sourceGroupId = sourceGroupId, group.id == sourceGroupId {
                            EmptyView()
                        } else {
                            Button {
                                if mode == .move {
                                    // 移動の場合は1つのみ選択
                                    selectedGroupIds = [group.id]
                                } else {
                                    // コピーの場合は複数選択可能
                                    if selectedGroupIds.contains(group.id) {
                                        selectedGroupIds.remove(group.id)
                                    } else {
                                        selectedGroupIds.insert(group.id)
                                    }
                                }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(group.name)
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                        Text("\(group.questionIds.count)問")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    if selectedGroupIds.contains(group.id) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.blue)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())  // Make entire row tappable
                                .padding(.vertical, 8)  // Add vertical padding for easier tapping
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text("既存のグループ")
                }
            }
            .navigationTitle(mode == .move ? "移動先を選択" : "コピー先を選択")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("決定") {
                        performAction()
                    }
                    .disabled(!canPerformAction())
                }
            }
            .alert("エラー", isPresented: $showActionError) {
                Button("OK") { }
            } message: {
                Text(actionError ?? "不明なエラーが発生しました")
            }
        }
    }
    
    private func canPerformAction() -> Bool {
        var hasValidDestination = false
        
        // Check if new group creation is enabled and valid
        if showNewGroupField && !newGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            hasValidDestination = true
        }
        
        // Check if at least one existing group is selected
        if !selectedGroupIds.isEmpty {
            hasValidDestination = true
        }
        
        // For move mode, ensure exactly one destination
        if mode == .move {
            let totalDestinations = (showNewGroupField && !newGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 1 : 0) + selectedGroupIds.count
            return totalDestinations == 1
        }
        
        // For copy mode, at least one destination is required
        return hasValidDestination
    }
    
    private func performAction() {
        #if DEBUG
        // Temporary debug logs
        print("[Move/Copy] mode=\(mode == .move ? "move" : "copy")")
        print("[Move/Copy] sourceGroupId=\(String(describing: sourceGroupId))")
        print("[Move/Copy] questionIds.count=\(questionIds.count), questionIds=\(questionIds)")
        #endif
        
        // Validate inputs BEFORE any operations
        guard !questionIds.isEmpty else {
            #if DEBUG
            print("❌ [Move/Copy] questionIds is empty")
            #endif
            actionError = "問題が選択されていません"
            showActionError = true
            return
        }
        
        // For move, sourceGroupId is required
        if mode == .move {
            guard let sourceGroupId = sourceGroupId else {
                #if DEBUG
                print("❌ [Move/Copy] sourceGroupId is nil for move operation")
                #endif
                actionError = "移動元のグループが指定されていません"
                showActionError = true
                return
            }
            
            // Verify source group exists
            guard model.pack.groups.contains(where: { $0.id == sourceGroupId }) else {
                #if DEBUG
                print("❌ [Move/Copy] source group does not exist: \(sourceGroupId)")
                #endif
                actionError = "移動元のグループが見つかりません"
                showActionError = true
                return
            }
        }
        
        // Build destination group IDs
        var targetGroupIds: [UUID] = []
        
        // Create new group if requested
        if showNewGroupField && !newGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let trimmedName = newGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
            let newGroup = QuestionGroup(name: trimmedName)
            model.addGroup(newGroup)
            targetGroupIds.append(newGroup.id)
            #if DEBUG
            print("[Move/Copy] created new group: \(newGroup.id)")
            #endif
        }
        
        // Add selected existing groups
        targetGroupIds.append(contentsOf: selectedGroupIds)
        #if DEBUG
        print("[Move/Copy] dest.count=\(targetGroupIds.count), destIds=\(targetGroupIds)")
        #endif
        
        // Validate destination
        guard !targetGroupIds.isEmpty else {
            #if DEBUG
            print("❌ [Move/Copy] no destination groups selected")
            #endif
            actionError = "移動先（またはコピー先）のグループが選択されていません"
            showActionError = true
            return
        }
        
        // For move, exactly one destination is required
        if mode == .move {
            guard targetGroupIds.count == 1, let destinationGroupId = targetGroupIds.first else {
                #if DEBUG
                print("❌ [Move/Copy] move requires exactly one destination, got \(targetGroupIds.count)")
                #endif
                actionError = "移動先は1つのグループのみ選択できます"
                showActionError = true
                return
            }
            
            guard let sourceGroupId = sourceGroupId else {
                // This should not happen due to earlier guard, but double-check
                actionError = "移動元のグループが指定されていません"
                showActionError = true
                return
            }
            
            // Skip if moving to same group
            guard sourceGroupId != destinationGroupId else {
                #if DEBUG
                print("⚠️ [Move/Copy] skipping move to same group")
                #endif
                dismiss()
                return
            }
            
            // Verify destination group exists
            guard model.pack.groups.contains(where: { $0.id == destinationGroupId }) else {
                #if DEBUG
                print("❌ [Move/Copy] destination group does not exist: \(destinationGroupId)")
                #endif
                actionError = "移動先のグループが見つかりません"
                showActionError = true
                return
            }
            
            // Perform move operation (AppModel is @MainActor, so this is already on main thread)
            #if DEBUG
            print("✅ [Move/Copy] executing move operation")
            #endif
            model.moveQuestions(questionIds: questionIds, fromGroupId: sourceGroupId, toGroupId: destinationGroupId)
            #if DEBUG
            print("✅ [Move/Copy] move operation completed, dismissing")
            #endif
            dismiss()
        } else {
            // Copy mode: verify all destination groups exist
            for destId in targetGroupIds {
                guard model.pack.groups.contains(where: { $0.id == destId }) else {
                    #if DEBUG
                    print("❌ [Move/Copy] destination group does not exist: \(destId)")
                    #endif
                    actionError = "コピー先のグループが見つかりません"
                    showActionError = true
                    return
                }
            }
            
            // Perform copy operation (AppModel is @MainActor, so this is already on main thread)
            #if DEBUG
            print("✅ [Move/Copy] executing copy operation")
            #endif
            model.copyQuestions(questionIds: questionIds, toGroupIds: targetGroupIds)
            #if DEBUG
            print("✅ [Move/Copy] copy operation completed, dismissing")
            #endif
            dismiss()
        }
    }
}
