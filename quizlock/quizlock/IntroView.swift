import SwiftUI

struct IntroView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 40) {
            Spacer()
            
            VStack(spacing: 20) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 72))
                    .foregroundStyle(.gray)
                
                VStack(spacing: 12) {
                    Text("Quiz Lock")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(.gray)
                    
                    Text("クイズで学習時間を守る")
                        .font(.title3)
                        .foregroundStyle(.gray.opacity(0.8))
                }
                
                Text("勉強時間中は、ロック解除にクイズが必要です。\nまず問題を作成してください。")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.gray.opacity(0.7))
                    .padding(.horizontal, 32)
            }

            Spacer()

            Button {
                model.setSeenIntro()
            } label: {
                Text("始める")
                    .font(.headline)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.gray)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 50)
        }
        .background(Color(white: 0.95))
    }
}
