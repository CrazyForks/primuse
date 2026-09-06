import Foundation
import Network

/// Route health needs transport evidence. Service responses, trust decisions,
/// cancellation and unknown errors must not quarantine a reachable endpoint.
public enum SourceNetworkFailurePolicy {
    public static func isNetworkFailure(_ error: any Error) -> Bool {
        classify(error, depth: 0)
    }

    private static func classify(_ error: any Error, depth: Int) -> Bool {
        guard depth < 8, !(error is CancellationError) else { return false }
        if let networkError = error as? NWError {
            switch networkError {
            case .posix(let code): return isNetworkPOSIXCode(Int(code.rawValue))
            case .dns: return true
            default: return false
            }
        }

        let error = error as NSError
        if error.domain == NSURLErrorDomain {
            switch URLError.Code(rawValue: error.code) {
            case .timedOut, .cannotFindHost, .cannotConnectToHost,
                 .networkConnectionLost, .dnsLookupFailed, .notConnectedToInternet:
                return true
            default:
                return false
            }
        }
        if error.domain == NSPOSIXErrorDomain {
            return isNetworkPOSIXCode(error.code)
        }
        if error.domain == NSCocoaErrorDomain, error.code == NSUserCancelledError {
            return false
        }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? any Error {
            return classify(underlying, depth: depth + 1)
        }
        return false
    }

    private static func isNetworkPOSIXCode(_ code: Int) -> Bool {
        [ENETDOWN, ENETUNREACH, ENETRESET, ECONNABORTED, ECONNRESET,
         ENOTCONN, ETIMEDOUT, ECONNREFUSED, EHOSTDOWN, EHOSTUNREACH, EPIPE]
            .contains { Int($0) == code }
    }
}
