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
  t.formatted(
    .number
      .precision(.fractionLength(4))
      .locale(Locale(identifier: "en_US_POSIX"))
  )
}

func printError(_ message: String) {
  FileHandle.standardError.write(Data("\(message)\n".utf8))
}

func seconds(_ duration: Duration) -> TimeInterval {
  let parts = duration.components
  return max(
    0,
    Double(parts.seconds) + Double(parts.attoseconds) / 1_000_000_000_000_000_000
  )
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
        let clock = ContinuousClock()
        let start = clock.now
        _ = await enumerateEjectableVolumes()
        timings.append(seconds(start.duration(to: clock.now)))
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
        printError("ERROR: eject mode requires --confirm-eject YES")
        return 2
      }

      var timings: [TimeInterval] = []
      timings.reserveCapacity(config.iterations)

      for _ in 0..<config.iterations {
        let clock = ContinuousClock()
        let start = clock.now
        let result = await ejectAllExternalVolumes(options: .default)
        timings.append(seconds(start.duration(to: clock.now)))

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
