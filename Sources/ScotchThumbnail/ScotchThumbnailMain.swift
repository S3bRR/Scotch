import Darwin

@_silgen_name("NSExtensionMain")
private func NSExtensionMain(
    _ argc: Int32,
    _ argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
) -> Int32

@main
struct ScotchThumbnailMain {
    static func main() {
        let argc = Int32(CommandLine.argc)
        let status = CommandLine.unsafeArgv.withMemoryRebound(
            to: UnsafeMutablePointer<CChar>?.self,
            capacity: Int(argc)
        ) { argv in
            NSExtensionMain(argc, argv)
        }
        Darwin.exit(status)
    }
}
