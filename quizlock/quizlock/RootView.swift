import SwiftUI

struct RootView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Group {
            if model.hasSeenIntro {
                HomeView()
            } else {
                IntroView()
            }
        }
        .background(Color(white: 0.95))
    }
}
