import Foundation

public struct AppleMusicLibraryAccess: Equatable, Sendable {
    public var storefrontCountryCode: String?
    public var canPlayCatalogContent: Bool
    public var canBecomeSubscriber: Bool

    public init(storefrontCountryCode: String?, canPlayCatalogContent: Bool, canBecomeSubscriber: Bool) {
        self.storefrontCountryCode = storefrontCountryCode?.uppercased()
        self.canPlayCatalogContent = canPlayCatalogContent
        self.canBecomeSubscriber = canBecomeSubscriber
    }

    public var syncMode: AppleMusicLibrarySyncMode {
        canPlayCatalogContent ? .authoritative : .partialFallback
    }

    public func canCommit(comparedTo latest: Self) -> Bool {
        self == latest
    }

    public func storefrontChanged(since previousCountryCode: String?) -> Bool {
        guard let previousCountryCode, let storefrontCountryCode else { return false }
        return previousCountryCode.uppercased() != storefrontCountryCode
    }
}
