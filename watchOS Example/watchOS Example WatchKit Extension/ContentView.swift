
import Alamofire
import SwiftUI

struct ContentView: View {
    @ObservedObject var networking: Networking

    var body: some View {
        VStack {
            Button(action: { networking.performRequest() },
                   label: { Text("Perform Request") })
            Text(networking.message)
        }
    }
}

struct ContentViewPreviews: PreviewProvider {
    static let networking = Networking()

    static var previews: some View {
        ContentView(networking: networking)
    }
}
