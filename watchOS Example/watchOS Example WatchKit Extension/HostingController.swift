
import Foundation
import SwiftUI
import WatchKit

class HostingController: WKHostingController<ContentView> {
    let networking = Networking()

    override var body: ContentView {
        ContentView(networking: networking)
    }
}
