import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        SpeechListView()
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Speech.self, inMemory: true)
}
