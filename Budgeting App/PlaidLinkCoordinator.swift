import Foundation
import Combine
import UIKit

#if canImport(LinkKit)
import LinkKit
#endif

@MainActor
final class PlaidLinkCoordinator: ObservableObject {
    #if canImport(LinkKit)
    private var handler: Handler?
    #endif

    func open(
        linkToken: String,
        onSuccess: @escaping (_ publicToken: String, _ institutionName: String?) -> Void,
        onExit: @escaping (_ errorDescription: String?) -> Void
    ) {
        #if canImport(LinkKit)
        var configuration = LinkTokenConfiguration(token: linkToken) { success in
            onSuccess(success.publicToken, success.metadata.institution.name)
        }
        configuration.onExit = { exit in
            if let error = exit.error {
                let code = String(describing: error.errorCode)
                onExit("\(error.errorMessage) (\(code))")
            } else {
                onExit(nil)
            }
        }

        let result = Plaid.create(configuration)
        switch result {
        case .failure(let error):
            onExit(error.localizedDescription)
        case .success(let handler):
            self.handler = handler
            guard let presenter = UIApplication.shared.activeRootViewController else {
                onExit("Could not find a view controller to present Plaid Link.")
                return
            }
            handler.open(presentUsing: .viewController(presenter))
        }
        #else
        onExit("LinkKit is not available. Resolve the Plaid SPM package in Xcode first.")
        #endif
    }

    func resume(from url: URL) {
        #if canImport(LinkKit)
        let redirectURL: URL
        if url.scheme?.caseInsensitiveCompare("momosmoney") == .orderedSame,
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let encodedRedirect = components.queryItems?.first(where: { $0.name == "redirect_uri" })?.value,
           let originalRedirect = URL(string: encodedRedirect) {
            redirectURL = originalRedirect
        } else {
            redirectURL = url
        }
        handler?.resumeAfterTermination(from: redirectURL)
        #else
        _ = url
        #endif
    }
}

private extension UIApplication {
    var activeRootViewController: UIViewController? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .rootViewController?
            .topMostPresented
    }
}

private extension UIViewController {
    var topMostPresented: UIViewController {
        var current = self
        while let presented = current.presentedViewController {
            current = presented
        }
        return current
    }
}
