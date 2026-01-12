import SwiftUI

/// 時間と分を分けて設定するPicker（解除時間・使用時間制限用）
/// 「x時間y分」形式で表示
struct DurationPicker: View {
    @Binding var totalMinutes: Int
    var allowZero: Bool = false  // 0分を許可するか（使用時間制限用）
    
    var body: some View {
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        
        HStack(spacing: 0) {
            // 時間ホイール
            Picker("", selection: Binding(
                get: { hours },
                set: { newHours in
                    let newTotal = newHours * 60 + minutes
                    if !allowZero && newTotal == 0 {
                        totalMinutes = 1  // 最小1分
                    } else {
                        totalMinutes = newTotal
                    }
                }
            )) {
                ForEach(0..<24, id: \.self) { hour in
                    Text("\(hour)")
                        .tag(hour)
                }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
            
            Text("時間")
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            
            // 分ホイール
            Picker("", selection: Binding(
                get: { minutes },
                set: { newMinutes in
                    let newTotal = hours * 60 + newMinutes
                    if !allowZero && newTotal == 0 {
                        totalMinutes = 1  // 最小1分
                    } else {
                        totalMinutes = newTotal
                    }
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
