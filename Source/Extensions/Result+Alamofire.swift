
import Foundation

public typealias AFResult<Success> = Result<Success, AFError>

extension Result {
    var isSuccess: Bool {
        guard case .success = self else { return false }
        return true
    }

    var isFailure: Bool {
        !isSuccess
    }

    var success: Success? {
        guard case let .success(value) = self else { return nil }
        return value
    }

    var failure: Failure? {
        guard case let .failure(error) = self else { return nil }
        return error
    }

    init(value: Success, error: Failure?) {
        if let error {
            self = .failure(error)
        } else {
            self = .success(value)
        }
    }

    func tryMap<NewSuccess>(_ transform: (Success) throws -> NewSuccess) -> Result<NewSuccess, any Error> {
        switch self {
        case let .success(value):
            do {
                return try .success(transform(value))
            } catch {
                return .failure(error)
            }
        case let .failure(error):
            return .failure(error)
        }
    }

    func tryMapError<NewFailure: Error>(_ transform: (Failure) throws -> NewFailure) -> Result<Success, any Error> {
        switch self {
        case let .failure(error):
            do {
                return try .failure(transform(error))
            } catch {
                return .failure(error)
            }
        case let .success(value):
            return .success(value)
        }
    }
}
