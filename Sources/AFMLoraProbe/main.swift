// AFMLoraProbe — minimal reproducer for the AFM LoRA APFS-metadata disk leak.
//
// See: https://developer.apple.com/forums/thread/823001
//
// This binary does the least work possible so that any disk activity observed
// during its run is attributable to FoundationModels / TGOnDeviceInferenceProviderService.
// It prints its PID and structured timestamps so the wrapping trace script can
// correlate fs_usage / log-stream events with adapter load and per-call windows.

import Foundation
import JuncoKit

@main
enum AFMLoraProbe {

  static func main() async throws {
    let args = parse(CommandLine.arguments.dropFirst())

    print("PID=\(getpid())")
    print("READY_NS=\(DispatchTime.now().uptimeNanoseconds)")
    fflush(stdout)

    try await Task.sleep(nanoseconds: UInt64(args.delayBefore) * 1_000_000_000)

    let adapter = AFMAdapter()

    if args.noAdapter {
      print("ADAPTER_MODE=none")
    } else if let path = args.adapterPath {
      print("ADAPTER_MODE=fileURL path=\(path)")
      await adapter.loadAdapter(from: URL(fileURLWithPath: path))
    } else {
      print("ADAPTER_MODE=named name=\(args.adapterName)")
      await adapter.loadAdapter(named: args.adapterName)
    }
    let loaded = await adapter.hasAdapter
    print("ADAPTER_LOADED=\(loaded)")
    fflush(stdout)

    let prompts = [
      "Reply with just the number 42.",
      "Reply with just the word hello.",
      "Reply with just the letter A."
    ]

    for i in 0..<args.calls {
      let prompt = prompts[i % prompts.count]
      print("CALL_\(i)_START_NS=\(DispatchTime.now().uptimeNanoseconds)")
      fflush(stdout)
      do {
        let response = try await adapter.generate(prompt: prompt, system: nil)
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        let preview = trimmed.prefix(40).replacingOccurrences(of: "\n", with: " ")
        print("CALL_\(i)_END_NS=\(DispatchTime.now().uptimeNanoseconds) out=\"\(preview)\"")
      } catch {
        print("CALL_\(i)_ERROR_NS=\(DispatchTime.now().uptimeNanoseconds) err=\"\(error)\"")
      }
      fflush(stdout)
    }

    print("DONE_NS=\(DispatchTime.now().uptimeNanoseconds)")
  }

  // MARK: - Arg parsing

  private struct Args {
    var adapterName: String = "junco_coding"
    var adapterPath: String?
    var noAdapter: Bool = false
    var calls: Int = 3
    var delayBefore: Int = 3
  }

  private static func parse(_ argv: ArraySlice<String>) -> Args {
    var out = Args()
    var it = argv.makeIterator()
    while let a = it.next() {
      switch a {
      case "--adapter-name":
        if let v = it.next() { out.adapterName = v }
      case "--adapter-path":
        if let v = it.next() { out.adapterPath = v }
      case "--no-adapter":
        out.noAdapter = true
      case "--calls":
        if let v = it.next(), let n = Int(v) { out.calls = n }
      case "--delay-before":
        if let v = it.next(), let n = Int(v) { out.delayBefore = n }
      default:
        FileHandle.standardError.write(Data("warning: ignoring unknown arg \(a)\n".utf8))
      }
    }
    return out
  }
}
