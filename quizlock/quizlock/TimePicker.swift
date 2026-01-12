import SwiftUI

/// iOS Screen Timeスタイルの時間ピッカー（ホイール形式）
struct TimePicker: View {
    @Binding var minutes: Int  // 0-1439（分単位）
    
    var body: some View {
        let hours = minutes / 60
        let mins = minutes % 60
        
        HStack(spacing: 0) {
            // 時間ホイール
            Picker("", selection: Binding(
                get: { hours },
                set: { newHours in
                    minutes = newHours * 60 + mins
                }
            )) {
                ForEach(0..<24, id: \.self) { hour in
                    Text("\(hour)")
                        .tag(hour)
                }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
            
            Text("時")
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            
            // 分ホイール
            Picker("", selection: Binding(
                get: { mins },
                set: { newMins in
                    minutes = hours * 60 + newMins
                }
            )) {
                ForEach(0..<60, id: \.self) { minute in
                    Text("\(minute)")
                        .tag(minute)
                }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
            
            Text("分")
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
        .frame(height: 120)
    }
}
