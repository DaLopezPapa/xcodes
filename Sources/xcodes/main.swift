import Foundation
import ArgumentParser
import Version
import PromiseKit
import XcodesKit
import LegibleError
import Path

var configuration = Configuration()
try? configuration.load()
let xcodeList = XcodeList()
let installer = XcodeInstaller(configuration: configuration, xcodeList: xcodeList)

migrateApplicationSupportFiles()

struct Xcodes: ParsableCommand {
    static var configuration = CommandConfiguration(
        abstract: "Manage the Xcodes installed on your Mac",
        shouldDisplay: true,
        subcommands: [Install.self, Installed.self, List.self, Select.self, Uninstall.self, Update.self, Version.self]
    )

    struct Install: ParsableCommand {
        static var configuration = CommandConfiguration(
            abstract: "Download and install a specific version of Xcode",
            discussion: """
                        EXAMPLES:
                          xcodes install 10.2.1
                          xcodes install 11 Beta 7
                          xcodes install 11.2 GM seed
                          xcodes install 9.0 --url ~/Archive/Xcode_9.xip
                        """
        )

        @Argument(help: "The version to install",
                  completion: .custom { args in xcodeList.availableXcodes.sorted { $0.version < $1.version }.map { $0.version.xcodeDescription } })
        var version: [String] = []
        
        @Option(help: "Local path to Xcode .xip",
                completion: .file(extensions: ["xip"]))
        var url: String?
            
        func run() {
            installer.install(version.joined(separator: " "), url)
                .done { Install.exit() }
                .catch { error in
                    switch error {
                    case Process.PMKError.execution(let process, let standardOutput, let standardError):
                        Current.logging.log("""
                            Failed executing: `\(process)` (\(process.terminationStatus))
                            \([standardOutput, standardError].compactMap { $0 }.joined(separator: "\n"))
                            """)
                    default:
                        Current.logging.log(error.legibleLocalizedDescription)
                    }

                    Install.exit(withError: ExitCode.failure)
                }

            RunLoop.current.run()
        }
    }

    struct Installed: ParsableCommand {
        static var configuration = CommandConfiguration(
            abstract: "List the versions of Xcode that are installed"
        )
        
        func run() {
            installer.printInstalledXcodes()
                .done { Installed.exit() }
                .catch { error in Installed.exit(withLegibleError: error) }

            RunLoop.current.run()
        }
    }
    
    struct List: ParsableCommand {
        static var configuration = CommandConfiguration(
            abstract: "List all versions of Xcode that are available to install"
        )
        
        func run() {
            firstly { () -> Promise<Void> in
                if xcodeList.shouldUpdate {
                    return installer.updateAndPrint()
                }
                else {
                    return installer.printAvailableXcodes(xcodeList.availableXcodes, installed: Current.files.installedXcodes())
                }
            }
            .done { List.exit() }
            .catch { error in List.exit(withLegibleError: ExitCode.failure) }

            RunLoop.current.run()
        }
    }
    
    struct Select: ParsableCommand {
        static var configuration = CommandConfiguration(
            abstract: "Change the selected Xcode",
            discussion: """
                        Run without any arguments to interactively select from a list, or provide an absolute path.

                        EXAMPLES:
                          xcodes select
                          xcodes select 11.4.0
                          xcodes select /Applications/Xcode-11.4.0.app
                          xcodes select -p
                        """
        )
        
        @ArgumentParser.Flag(name: [.customShort("p"), .customLong("print-path")], help: "Print the path of the selected Xcode")
        var print: Bool = false
        
        @Argument(help: "Version or path",
                  completion: .custom { _ in Current.files.installedXcodes().sorted { $0.version < $1.version }.map { $0.version.xcodeDescription } })
        var versionOrPath: [String] = []
    
        func run() {
            selectXcode(shouldPrint: print, pathOrVersion: versionOrPath.joined(separator: " "))
                .done { Select.exit() }
                .catch { error in Select.exit(withLegibleError: error) }
            
            RunLoop.current.run()
        }
    }
    
    struct Uninstall: ParsableCommand {
        static var configuration = CommandConfiguration(
            abstract: "Uninstall a specific version of Xcode",
            discussion: """
                        EXAMPLES:
                          xcodes uninstall 10.2.1
                        """
        )
        
        @Argument(help: "The version to uninstall",
                  completion: .custom { _ in Current.files.installedXcodes().sorted { $0.version < $1.version }.map { $0.version.xcodeDescription } })
        var version: [String] = []
        
        func run() {
            installer.uninstallXcode(version.joined(separator: " "))
                .done { Uninstall.exit() }
                .catch { error in Uninstall.exit(withLegibleError: ExitCode.failure) }
        
            RunLoop.current.run()
        }
    }
    
    struct Update: ParsableCommand {
        static var configuration = CommandConfiguration(
            abstract: "Update the list of available versions of Xcode"
        )
        
        func run() {
            installer.updateAndPrint()
                .done { Update.exit() }
                .catch { error in Update.exit(withLegibleError: error) }

            RunLoop.current.run()
        }
    }
    
    struct Version: ParsableCommand {
        static var configuration = CommandConfiguration(
            abstract: "Print the version number of xcodes itself"
        )
        
        func run() {
            Current.logging.log(XcodesKit.version.description)
        }
    }
}

Xcodes.main()
