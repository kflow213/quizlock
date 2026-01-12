import SwiftUI

struct GroupSelectionView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    
    var sortedGroups: [QuestionGroup] {
        // 選択されたグループを一番上に表示
        let selectedGroups = model.pack.groups.filter { model.pack.selectedGroupIds.contains($0.id) }
        let unselectedGroups = model.pack.groups.filter { !model.pack.selectedGroupIds.contains($0.id) }
        return selectedGroups + unselectedGroups
    }
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(sortedGroups) { group in
                    Button {
                        toggleGroupSelection(group.id)
                    } label: {
                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(isSelected(group.id) ? .white : Color.accentColor)
                            Text(group.name)
                                .font(.headline)
                                .foregroundStyle(isSelected(group.id) ? .white : .primary)
                            Spacer()
                            
                            if isSelected(group.id) {
                                Text("選択中")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.9))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.white.opacity(0.2))
                                    .clipShape(Capsule())
                            }
                            
                            Text("\(group.questionIds.count)問")
                                .font(.caption)
                                .foregroundStyle(isSelected(group.id) ? .white.opacity(0.8) : .secondary)
                        }
                        .padding()
                        .background(isSelected(group.id) ? Color.accentColor : Color(uiColor: .systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(white: 0.95))
            .navigationTitle("出題グループを選択")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func isSelected(_ groupId: UUID) -> Bool {
        model.pack.selectedGroupIds.contains(groupId)
    }
    
    private func toggleGroupSelection(_ groupId: UUID) {
        model.toggleGroupSelection(groupId)
    }
}
