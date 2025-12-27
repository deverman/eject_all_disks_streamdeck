# Disk Ejection Benchmark Suite

Comprehensive benchmarking tools to measure and compare disk ejection performance.

## Quick Start

### Automated Benchmark

```bash
cd benchmark
chmod +x benchmark-suite.sh

# Run with test disk images (safest for repeated testing)
./benchmark-suite.sh --create-dmgs 3 --runs 10 --output results.json

# Run with your actual external disks
./benchmark-suite.sh --runs 5 --output results.json

# Skip Jettison comparison if not installed
./benchmark-suite.sh --runs 5 --skip-jettison --output results.json
```

### Generate Reports

```bash
# Generate markdown and HTML reports
python3 analyze-results.py results.json

# Open the HTML report
open results/benchmark_*_report.html
```

## What Gets Benchmarked

1. **Native API (this plugin)**: Direct DiskArbitration framework calls
2. **diskutil subprocess**: Traditional command-line approach
3. **Jettison** (optional): Commercial competitor, if installed

## Benchmark Options

### `benchmark-suite.sh`

- `--runs N` - Number of test runs per method (default: 5)
  - More runs = more accurate averages
  - Recommended: 10 for marketing claims, 5 for quick tests

- `--create-dmgs N` - Create N test disk images
  - Best for repeatable testing
  - Auto-cleanup on completion
  - Recommended: 3-5 DMGs

- `--skip-jettison` - Skip Jettison benchmarks
  - Use if Jettison not installed
  - Faster testing

- `--output FILE` - Save results to JSON file
  - Required for analysis scripts
  - Example: `--output my-results.json`

## Understanding Results

### Metrics Reported

- **Average Time**: Mean ejection time across all runs
- **Min/Max Time**: Fastest and slowest runs
- **Standard Deviation**: Consistency of performance
- **Speedup Factor**: How much faster native API is vs competitors

### Example Output

```
Method                    Avg Time   Speedup
-------------------------  ----------  ----------
Native API                0.6234s    1.00x
diskutil subprocess       5.8912s    9.45x
Jettison                  3.2156s    5.16x
```

**Interpretation**: Native API is **9.5x faster than diskutil** and **5.2x faster than Jettison**.

## Manual Testing

For one-off comparisons:

```bash
cd ..

# Test native API
time org.deverman.ejectalldisks.sdPlugin/bin/eject-disks eject

# Remount your volumes, then...

# Test diskutil method
time org.deverman.ejectalldisks.sdPlugin/bin/eject-disks eject --use-diskutil
```

## Tips for Accurate Benchmarks

### 1. Use Test Disk Images

Real USB drives have variable performance. For consistent results:

```bash
./benchmark-suite.sh --create-dmgs 5 --runs 10
```

This creates 5 × 10MB disk images, runs 10 tests per method, and cleans up automatically.

### 2. Warm Up the System

Run one test first to warm up caches:

```bash
# Warm-up run
./benchmark-suite.sh --runs 1 --skip-jettison

# Real benchmark
./benchmark-suite.sh --runs 10 --output production-results.json
```

### 3. Minimize Background Activity

For marketing benchmarks:

- Close all apps
- Disable Spotlight indexing temporarily: `sudo mdutil -a -i off`
- Disable Time Machine
- Don't use the computer during benchmarking

Re-enable Spotlight after: `sudo mdutil -a -i on`

### 4. Test Different Scenarios

```bash
# Scenario 1: Small number of disks (realistic)
./benchmark-suite.sh --create-dmgs 2 --runs 10 --output scenario-2disks.json

# Scenario 2: Many disks (stress test)
./benchmark-suite.sh --create-dmgs 8 --runs 10 --output scenario-8disks.json

# Scenario 3: Real-world USB drives
# (Mount 3 actual USB drives, then:)
./benchmark-suite.sh --runs 10 --output scenario-usb.json
```

## Troubleshooting

### "No ejectable volumes found"

Make sure you have external disks mounted, or use `--create-dmgs`:

```bash
./benchmark-suite.sh --create-dmgs 3
```

### "Jettison not found"

Jettison is optional. Either:

1. Install Jettison from https://www.stclairsoft.com/Jettison/
2. Use `--skip-jettison` to skip it

### Permission Errors

Make sure the script is executable:

```bash
chmod +x benchmark-suite.sh
```

### Incomplete Remounting

If using real disks, you must manually remount between tests. The script will pause and wait for you to:

1. Reconnect USB drives (or use Disk Utility to remount)
2. Press Enter to continue

## Output Files

After running benchmarks, you'll find:

```
benchmark/results/
├── benchmark_20250127_143022.json           # Raw JSON data
├── benchmark_20250127_143022_report.md      # Markdown report
├── benchmark_20250127_143022_report.html    # HTML report
├── benchmark_20250127_143022_native.txt     # Native API logs
├── benchmark_20250127_143022_diskutil.txt   # diskutil logs
└── benchmark_20250127_143022_jettison.txt   # Jettison logs
```

## Using Results for Marketing

The generated reports are ready for marketing use:

### Markdown Report

Perfect for README.md or documentation:

```bash
# Copy key findings to main README
cat results/benchmark_*_report.md >> ../README.md
```

### HTML Report

Share with stakeholders or post on website:

```bash
# Open in browser
open results/benchmark_*_report.html

# Or publish to GitHub Pages
cp results/benchmark_*_report.html ../docs/benchmark-results.html
```

### JSON Data

Use for custom analysis, charts, or graphs:

```python
import json
with open('results.json') as f:
    data = json.load(f)
    speedup = data['results']['diskutil']['speedup']
    print(f"We're {speedup:.1f}x faster!")
```

## Continuous Benchmarking

Add to CI/CD pipeline:

```yaml
# .github/workflows/benchmark.yml
name: Benchmark
on: [push]
jobs:
  benchmark:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v2
      - name: Run benchmarks
        run: |
          cd benchmark
          ./benchmark-suite.sh --create-dmgs 3 --runs 5 --output results.json
      - name: Generate reports
        run: python3 benchmark/analyze-results.py benchmark/results.json
      - name: Upload results
        uses: actions/upload-artifact@v2
        with:
          name: benchmark-results
          path: benchmark/results/*_report.*
```

## Advanced: Custom Analysis

The JSON output includes all raw data for custom analysis:

```python
import json
import matplotlib.pyplot as plt

with open('results.json') as f:
    data = json.load(f)

methods = ['Native', 'diskutil', 'Jettison']
times = [
    data['results']['native']['avgTime'],
    data['results']['diskutil']['avgTime'],
    data['results']['jettison']['avgTime']
]

plt.bar(methods, times)
plt.ylabel('Time (seconds)')
plt.title('Disk Ejection Performance')
plt.savefig('benchmark-chart.png')
```
