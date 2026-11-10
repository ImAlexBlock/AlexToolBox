import SwiftUI
import HeadsetControl

@main
struct AlexToolBoxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var model = AppModel.shared
    @ObservedObject private var headset = HeadsetLink.shared

    var body: some Scene {
        MenuBarExtra {
            RootView(model: model)
        } label: {
            Image(systemName: headset.state.isConnected ? "headphones" : "computermouse")
                .accessibilityLabel("AlexToolBox")
        }
        .menuBarExtraStyle(.window)
    }
}
