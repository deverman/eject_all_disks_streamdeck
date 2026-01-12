import Foundation
import SwiftDiskArbitration

enum BenchMode: String {
  case enumerate
  case eject
}

struct BenchConfig {
  var mode: BenchMode = .enumerate
  var iterations: Int = 10
  var confirmEject: String? = nil
}

enum ParseOutcome {
  case help
  case config(BenchConfig)
  case invalid
}

func printUsage() {
  print(
    """
    USAGE:
      swiftdiskarb-bench <enumerate|eject> [--iterations N] [--confirm-eject YES]

    MODES:
      enumerate        Enumerate ejectable volumes and report timing (safe).
      eject            Eject all ejectable volumes. Requires --confirm-eject YES.

    OPTIONS:
      --iterations N   Number of iterations (default: 10)
      --confirm-eject  Safety interlock for eject mode (must be exactly YES)
      -h, --help       Show help
    """
  )
}

func parseArgs() -> ParseOutcome {
  var config = BenchConfig()
  var args = Array(CommandLine.arguments.dropFirst())

  if args.isEmpty || args.contains("-h") || args.contains("--help") {
    return .help
  }

  guard let first = args.first, !first.hasPrefix("-"), let mode = BenchMode(rawValue: first) else {
    return .invalid
  }
  args.removeFirst()
  config.mode = mode

  var i = 0
  while i < args.count {
    switch args[i] {
    case "-h", "--help":
      return .help
    case "--iterations":
      guard i + 1 < args.count, let n = Int(args[i + 1]), n > 0 else { return .invalid }
      config.iterations = n
      i += 2
    case "--confirm-eject":
      guard i + 1 < args.count else { return .invalid }
      config.confirmEject = args[i + 1]
      i += 2
    default:
      return .invalid
    }
  }

  return .config(config)
}

func formatSeconds(_ t: TimeInterval) -> String {
  String(format: "%.4f", t)
}

func runBench() async -> Int32 {
  let outcome = parseArgs()
  switch outcome {
  case .help:
    printUsage()
    return 0
  case .invalid:
    printUsage()
    return 2
  case .config(let config):
    switch config.mode {
    case .enumerate:
      var timings: [TimeInterval] = []
      timings.reserveCapacity(config.iterations)

      for _ in 0..<config.iterations {
        let start = Date()
        _ = await DiskSession.shared.enumerateEjectableVolumes()
        timings.append(Date().timeIntervalSince(start))
      }

      let total = timings.reduce(0, +)
      let mean = total / Double(timings.count)
      let minT = timings.min() ?? 0
      let maxT = timings.max() ?? 0

      print("mode=enumerate iterations=\(config.iterations)")
      print("mean_s=\(formatSeconds(mean)) min_s=\(formatSeconds(minT)) max_s=\(formatSeconds(maxT))")
      return 0

    case .eject:
      guard config.confirmEject == "YES" else {
        fputs("ERROR: eject mode requires --confirm-eject YES\n", stderr)
        return 2
      }

      var timings: [TimeInterval] = []
      timings.reserveCapacity(config.iterations)

      for _ in 0..<config.iterations {
        let start = Date()
        let result = await DiskSession.shared.ejectAllExternal(options: .default)
        timings.append(Date().timeIntervalSince(start))

        print(
          "eject_result success=\(result.successCount) failed=\(result.failedCount) total=\(result.totalCount) totalDuration_s=\(formatSeconds(result.totalDuration))"
        )
      }

      let total = timings.reduce(0, +)
      let mean = total / Double(timings.count)
      let minT = timings.min() ?? 0
      let maxT = timings.max() ?? 0

      print("mode=eject iterations=\(config.iterations)")
      print("mean_wall_s=\(formatSeconds(mean)) min_wall_s=\(formatSeconds(minT)) max_wall_s=\(formatSeconds(maxT))")
      return 0
    }
  }
}

@main
struct Runner {
  static func main() async {
    exit(await runBench())
  }
}
