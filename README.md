# NevBench

**NevBench** is a Linux benchmark script that measures CPU, Disk, and Network performance. It also automatically installs missing packages if needed (sudo required).

## Features

- CPU, Disk, and Network benchmarks
- Skip specific benchmarks: `--skip-cpu`, `--skip-disk`, `--skip-network`
- Clear screen before running: `--clear`
- Display system information before benchmarks
- Auto-install missing packages (sudo required)

## Requirements

- `jq`, `fio`, `sysbench`, `iperf3`, `ping`, `bc`, `awk`, `sed`, `curl`  
  *(will be installed automatically if missing)*

## Installation

Option 1: Clone repository

```bash
git clone https://github.com/proxynich/nevbench.git
cd nevbench
chmod +x nevbench.sh
````

Option 2: Run directly via wget or curl (no need to clone)

```bash
# Using wget
wget -qO- https://github.com/proxynich/nevbench/raw/main/nevbench.sh | sudo bash

# Using curl
curl -sL https://github.com/proxynich/nevbench/raw/main/nevbench.sh | sudo bash
```

You can also pass options directly:

```bash
wget -qO- https://github.com/proxynich/nevbench/raw/main/nevbench.sh | sudo bash -s -- --skip-disk --clear
```

## Usage

```bash
./nevbench.sh [OPTIONS]
```

### Options

| Option           | Description                            |
| ---------------- | -------------------------------------- |
| `--skip-cpu`     | Skip CPU benchmark                     |
| `--skip-disk`    | Skip Disk benchmark                    |
| `--skip-network` | Skip Network benchmark                 |
| `--clear`        | Clear screen before running benchmarks |
| `--help`         | Show this help message                 |

### Examples

```bash
./nevbench.sh                        # Run all benchmarks
./nevbench.sh --skip-disk            # Skip Disk benchmark
./nevbench.sh --skip-network --clear # Skip Network and clear screen
./nevbench.sh --help                 # Show help
```

Or using wget/curl directly:

```bash
wget -qO- https://github.com/proxynich/nevbench/raw/main/nevbench.sh | sudo bash -- --skip-disk --clear
```

## Example Output

```
▸ AES-NI             : ENABLED
▸ VM-x/AMD-V         : DISABLED
▸ Virtualization     : kvm
▸ OS                 : Debian GNU/Linux 12 (bookworm)
```

**I am not a professional developer.**
This script is just an experiment, please don't get mad at me.
Telegram : @ekcelsebastianus
