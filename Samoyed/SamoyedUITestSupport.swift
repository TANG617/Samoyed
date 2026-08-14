#if DEBUG
import Foundation

@MainActor
enum SamoyedUITestSupport {
    private static let fixtureKey = "SAMOYED_UI_TEST_FIXTURE"
    private static let resetKey = "SAMOYED_UI_TEST_RESET"
    private static let routeKey = "SAMOYED_UI_TEST_ROUTE"

    static func makeStoreIfRequested(
        processInfo: ProcessInfo = .processInfo,
        fileManager: FileManager = .default
    ) -> SamoyedStore? {
        guard let fixture = processInfo.environment[fixtureKey] else { return nil }

        // The app-group container survives process relaunches and test-runner reinstall cycles.
        // A dedicated subdirectory keeps fixtures isolated from the real shared document.
        let root = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: SamoyedSharedConfig.appGroupID
        ) ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let fileURL = root
            .appending(path: "SamoyedUITests", directoryHint: .isDirectory)
            .appending(path: "document.json")
        let repository = SamoyedDocumentRepository(fileURL: fileURL)

        if processInfo.environment[resetKey] == "1" {
            try? fileManager.removeItem(at: fileURL)
            SamoyedTintPreference.save(.ocean)
            prepareFixture(
                fixture,
                repository: repository,
                fileURL: fileURL,
                fileManager: fileManager
            )
        }

        enqueueExternalRouteIfRequested(processInfo: processInfo)

        return SamoyedStore(
            documentRepository: repository,
            validationLogger: ValidationEventLogger(enabled: false)
        )
    }

    private static func prepareFixture(
        _ fixture: String,
        repository: SamoyedDocumentRepository,
        fileURL: URL,
        fileManager: FileManager
    ) {
        if fixture == "load-error" {
            do {
                try fileManager.createDirectory(
                    at: fileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try Data("not-json".utf8).write(to: fileURL, options: .atomic)
            } catch {
                preconditionFailure("Unable to prepare load-error UI fixture: \(error)")
            }
            return
        }

        guard let document = SamoyedQAFixtureFactory.document(named: fixture) else {
            preconditionFailure("Unknown Samoyed UI test fixture: \(fixture)")
        }

        do {
            try repository.save(document)
        } catch {
            preconditionFailure("Unable to save Samoyed UI test fixture \(fixture): \(error)")
        }
    }

    private static func enqueueExternalRouteIfRequested(processInfo: ProcessInfo) {
        guard let routeValue = processInfo.environment[routeKey] else { return }
        guard
            let routeURL = URL(string: routeValue),
            SamoyedSystemRoute(url: routeURL) != nil
        else {
            preconditionFailure("Invalid Samoyed UI test route: \(routeValue)")
        }

        SamoyedExternalRouteCenter.shared.enqueue(routeURL)
    }
}
#endif
