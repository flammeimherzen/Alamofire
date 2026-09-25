
import Alamofire
import Combine

final class Networking: ObservableObject {
    @Published var result: Result<HTTPBinResponse, AFError>?
    @Published var message = "No response."

    private var storage: Set<AnyCancellable> = []

    init() {
        $result
            .compactMap(\.self)
            .map {
                if case .success = $0 {
                    "Successful!"
                } else {
                    "Failed!"
                }
            }
            .assign(to: \.message, on: self)
            .store(in: &storage)
    }

    func performRequest() {
        AF.request("https://httpbin.org/get").responseDecodable(of: HTTPBinResponse.self) { response in
            self.result = response.result
        }
    }
}

struct HTTPBinResponse: Decodable {
    let url: String
}
