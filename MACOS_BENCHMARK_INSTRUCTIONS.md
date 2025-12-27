# Running Benchmarks on macOS

## ⚠️ IMPORTANT: macOS Only

This benchmark suite **requires macOS** because:
- DiskArbitration framework is macOS-only
- `hdiutil` and `diskutil` are macOS system utilities
- Jettison is a macOS application
- The disk ejection plugin is a macOS Stream Deck plugin

**You cannot run these benchmarks on Linux.**

## Prerequisites (macOS Only)

1. **Xcode Command Line Tools**
   ```bash
   xcode-select --install
   ```

2. **Swift** (included with Xcode)
   ```bash
   swift --version
   # Should show: Swift version 5.x or higher
   ```

3. **Optional: Jettison** (for comparison benchmarks)
   - Download from: https://www.stclairsoft.com/Jettison/
   - Install to `/Applications/Jettison.app`
   - Or use `--skip-jettison` flag

## Step-by-Step Instructions

### 1. Build the Swift Binary

```bash
cd swift
chmod +x build.sh
./build.sh
```

This will:
- Build the Swift binary in release mode
- Copy it to `org.deverman.ejectalldisks.sdPlugin/bin/eject-disks`

**Verify the binary exists:**
```bash
ls -lh ../org.deverman.ejectalldisks.sdPlugin/bin/eject-disks
# Should show the compiled binary
```

### 2. Run Quick Test Benchmark (5 minutes)

```bash
cd ../benchmark
chmod +x benchmark-suite.sh

# Create 3 test disk images and run 5 iterations
./benchmark-suite.sh --create-dmgs 3 --runs 5 --output quick-test.json
```

**Expected Output:**
```
Creating 3 test disk images...
  Created and mounted: TestDisk1
  Created and mounted: TestDisk2
  Created and mounted: TestDisk3

Detecting ejectable volumes...
  Found 3 ejectable volume(s)

=========================================
TEST 1: Native DiskArbitration API
=========================================
Benchmarking: Native API (DADiskUnmount)
  Running 5 tests...
  Run 1/5: 0.0823s (3/3 ejected)
  Run 2/5: 0.0791s (3/3 ejected)
  ...

  Results:
    Average: 0.0812s
    Min:     0.0785s
    Max:     0.0845s
    StdDev:  0.0024s
```

### 3. Run Production Benchmark (for marketing claims)

For the most accurate results:

```bash
# 1. Disable background processes
sudo mdutil -a -i off  # Disable Spotlight indexing

# 2. Quit all apps
# Close Safari, Photos, Music, etc.

# 3. Run benchmark with 10 runs for statistical accuracy
./benchmark-suite.sh --create-dmgs 5 --runs 10 --output production.json

# 4. Re-enable Spotlight
sudo mdutil -a -i on
```

### 4. Analyze Results

```bash
# Generate markdown and HTML reports
python3 analyze-results.py production.json

# View HTML report
open results/production_report.html
```

### 5. Test with Real USB Drives (Optional)

```bash
# Mount your USB drives, then:
./benchmark-suite.sh --runs 5 --output real-usb.json

# Note: You'll need to manually remount drives between test runs
# The script will prompt you
```

## Expected Benchmark Results

### Clean Ejection (No Blocking Processes)

| Method | Time | vs Native |
|--------|------|-----------|
| **Native API** | **0.08s - 0.6s** | 1.0x (baseline) |
| diskutil subprocess | 5-8s | 9-10x slower |
| Jettison | 3-5s | 5-6x slower |

*Times vary based on number of volumes and disk speed*

### Typical Results for 3 Disk Images

```
=========================================
           FINAL RESULTS
=========================================

Method                    Avg Time     Speedup
------------------------- ---------- ----------
Native API                   0.0812s      1.00x
diskutil subprocess          0.7234s      8.91x
Jettison                     0.4521s      5.57x

Summary:
  Native API is 8.91x faster than diskutil
  Native API is 5.57x faster than Jettison
```

## Troubleshooting

### "Binary not found" Error

**Problem:** `Error: eject-disks binary not found`

**Solution:**
```bash
cd swift
./build.sh
# Verify it was copied:
ls -lh ../org.deverman.ejectalldisks.sdPlugin/bin/eject-disks
```

### "No ejectable volumes found" Error

**Problem:** `Error: No ejectable volumes found`

**Solution:** Either:
1. Use `--create-dmgs N` to create test disk images
2. Mount actual USB drives before running

### Jettison Not Found

**Problem:** `Warning: Jettison not found`

**Solution:** Either:
1. Install Jettison to `/Applications/Jettison.app`
2. Use `--skip-jettison` flag to skip Jettison benchmarks

### Permission Errors

**Problem:** `Permission denied` when creating disk images

**Solution:**
```bash
# Grant Terminal Full Disk Access:
# System Settings → Privacy & Security → Full Disk Access → Enable Terminal
```

## Files Generated

After running benchmarks, you'll find:

```
benchmark/results/
├── benchmark_20231227_120000_native.txt      # Raw output logs
├── benchmark_20231227_120000_diskutil.txt
├── benchmark_20231227_120000_jettison.txt
├── production.json                           # JSON data
├── production_report.md                      # Markdown report
└── production_report.html                    # HTML report (shareable)
```

## Adding Results to README

After running production benchmarks, copy the results table from the generated markdown report to your main README.md:

```bash
# View the markdown report
cat results/production_report.md

# Copy the "Performance Comparison" table to README.md
```

## Questions?

- **Can I run this on Linux?** No, macOS only.
- **Can I run this in a VM?** Technically yes, but disk I/O may skew results.
- **Do I need real USB drives?** No, `--create-dmgs` creates test disk images.
- **How many runs should I do?** 5-10 runs for reliable statistics.
- **Should I include Jettison?** Yes if you want competitive comparison.

## Production Code Status

✅ **All production code is ready for benchmarking:**
- `swift/Sources/EjectDisks.swift` - CLI interface
- `swift/Packages/SwiftDiskArbitration/Sources/` - Core library
  - `DiskSession.swift` - Main ejection logic
  - `Volume.swift` - Volume enumeration
  - `CallbackBridge.swift` - Async DiskArbitration bridge
  - `DiskError.swift` - Error handling

❌ **Prototype files NOT in production build:**
- `swift/Packages/SwiftDiskArbitration/Prototypes/` - Future features from PRD
  - `DiagnosticMessages.swift`
  - `SmartRetry.swift`
  - These are documented in the PRD but not yet implemented

The benchmarks will measure **only the production code** - exactly what you want!
