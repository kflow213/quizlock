import SwiftUI

/// Wrapper for QuestionEditorView that automatically adds newly created questions to a target group
struct QuestionEditorViewWithGroup: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let editing: Question?
    let targetGroupId: UUID?
    
    var body: some View {
        QuestionEditorView(editing: editing) { questionId in
            // Only called when a new question is actually saved (not on cancel)
            // Add the question to the target group
            if let groupId = targetGroupId {
                model.addQuestionToGroup(questionId: questionId, groupId: groupId)
            }
        }
    }
}
