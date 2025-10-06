#!/bin/bash
# Requires: bash, jq, fio, sysbench, iperf3, ping, bc, awk, sed, curl/wget

set -euo pipefail
IFS=$'\n\t'

RED="\033[0;31m"
YELLOW="\033[1;33m"
GREEN="\033[0;32m"
CYAN="\033[0;36m"
MAGENTA="\033[0;35m"
BOLD="\033[1m"
RESET="\033[0m"

WORKDIR="/tmp/bevo-$$"
FIO_SIZE="1G"
FIO_RUNTIME=10
FIO_IOENGINE="libaio"

IPERF_SERVERS=(
"Etisalat Group:UAE:86.96.154.106:7004"
"Datapacket:HK:84.17.57.129:5201"
"Arthatel:ID:iperf.scbd.net.id:5201"
"Satelit Nusantara:ID:103.185.255.183:5201"
"Datapacket:SG:89.187.162.1:5201"
"OVH:SG:sgp.proof.ovh.net:5204"
"Mirhosting:NL:speedtest.nl3.mirhosting.net:5201"
"Leaseweb:US:speedtest.sea11.us.leaseweb.net:5201"
"Gigahost:NO:lg.gigahost.no:9201"
"Scaleway:FR:ping.online.net:5200"
"Moji:FR:iperf3.moji.fr:5200"
)

cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

require_cmds() {
  local miss=()
  for c in "$@"; do command -v "$c" >/dev/null 2>&1 || miss+=("$c"); done
  if [ "${#miss[@]}" -gt 0 ]; then
    echo "Missing: ${miss[*]}"
    exit 1
  fi
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "Please run as root or with sudo"
        exit 1
    fi
}

detect_package_manager() {
    if command -v apt-get &> /dev/null; then
        PKG_MANAGER="apt"
    elif command -v yum &> /dev/null; then
        PKG_MANAGER="yum"
    elif command -v dnf &> /dev/null; then
        PKG_MANAGER="dnf"
    elif command -v pacman &> /dev/null; then
        PKG_MANAGER="pacman"
    elif command -v zypper &> /dev/null; then
        PKG_MANAGER="zypper"
    else
        echo "Unsupported package manager"
        exit 1
    fi
}

install_package() {
    local package=$1
    case $PKG_MANAGER in
        apt)
            DEBIAN_FRONTEND=noninteractive apt-get update -qq &> /dev/null
            DEBIAN_FRONTEND=noninteractive apt-get install -y $package &> /dev/null
            ;;
        yum)
            yum install -y $package &> /dev/null
            ;;
        dnf)
            dnf install -y $package &> /dev/null
            ;;
        pacman)
            pacman -Sy --noconfirm $package &> /dev/null
            ;;
        zypper)
            zypper install -y $package &> /dev/null
            ;;
    esac
}

check_and_install() {
    local cmd=$1
    local package=$2
    if ! command -v $cmd &> /dev/null; then
        install_package $package
    fi
}

install_dependencies() {
    detect_package_manager
    check_and_install fio fio
    check_and_install iperf3 iperf3
    check_and_install curl curl
    check_and_install jq jq
    check_and_install lscpu util-linux
    check_and_install bc bc
    check_and_install sysbench sysbench
    if [ "$PKG_MANAGER" = "apt" ]; then
        check_and_install dmidecode dmidecode
    fi
}

num_to_human() {
  local n=$1
  if (( $(echo "$n >= 1000000" | bc -l) )); then
    awk "BEGIN{printf \"%.1fM\", $n/1000000}"
  elif (( $(echo "$n >= 1000" | bc -l) )); then
    awk "BEGIN{printf \"%.1fk\", $n/1000}"
  else
    printf "%.0f" "$n"
  fi
}

color_speed() {
  local s=$1
  if (( $(echo "$s < 50" | bc -l) )); then echo -e "${RED}${s}${RESET}"
  elif (( $(echo "$s < 200" | bc -l) )); then echo -e "${YELLOW}${s}${RESET}"
  else echo -e "${GREEN}${s}${RESET}"
  fi
}

color_ping() {
  local p=$1
  if [[ "$p" == "N/A" ]]; then echo -e "${RED}N/A${RESET}"
  elif (( $(echo "$p < 50" | bc -l) )); then echo -e "${GREEN}${p}${RESET}"
  elif (( $(echo "$p < 150" | bc -l) )); then echo -e "${YELLOW}${p}${RESET}"
  else echo -e "${RED}${p}${RESET}"
  fi
}

color_status() {
  [[ "$1" =~ [Ee][Nn][Aa][Bb][Ll][Ee][Dd] ]] && echo -e "${GREEN}ENABLED${RESET}" || echo -e "${RED}DISABLED${RESET}"
}

sysinfo() {
  local cpu model freq cores cache aes virt vmx os arch kernel disk mem uptime load org loc ipv4 ipv6

  model="$(awk -F: '/model name/ {print $2; exit}' /proc/cpuinfo | sed 's/^ *//')"
  freq="$(awk -F: '/cpu MHz/ {print $2; exit}' /proc/cpuinfo | awk '{printf "%.2f", $1/1000}')"
  cores="$(nproc --all)"
  cache="$(awk -F: '/cache size/ {print $2; exit}' /proc/cpuinfo | sed 's/^ *//')"
  aes="$(grep -q aes /proc/cpuinfo && echo ENABLED || echo DISABLED)"
  vmx="$(grep -qiE 'vmx|svm' /proc/cpuinfo && echo ENABLED || echo DISABLED)"
  virt="$(systemd-detect-virt 2>/dev/null)"
  os="$(awk -F= '/^PRETTY_NAME/ {print $2}' /etc/os-release | tr -d '"')"
  arch="$(uname -m)"
  kernel="$(uname -r)"
  disk="$(df -h --total / | awk 'END{print $3" | "$2}')"
  mem="$(free -h --si | awk '/Mem:/ {print $3" | "$2}')"
  uptime="$(uptime -p | sed 's/up //')"
  load="$(awk '{print $1", "$2", "$3}' /proc/loadavg)"
  org="$(curl -s https://ipinfo.io/org || echo N/A)"
  tcp_cc="$(cat /proc/sys/net/ipv4/tcp_congestion_control)"
  loc="$(curl -s https://ipinfo.io/city 2>/dev/null), $(curl -s https://ipinfo.io/region 2>/dev/null)"
  ipv4=$(ip -4 addr show scope global | grep -q . && echo ENABLED || echo DISABLED)
  ipv6=$(ip -6 addr show scope global | grep -q . && echo ENABLED || echo DISABLED)

  echo -e "${BOLD}${CYAN}───────────────────────────────${RESET}"
  echo -e "${BOLD}${RED} NEVERDIE Benchmark v1.2 ${RESET}"
  echo -e "${BOLD} Script by Proxynich ${RESET}"
  echo -e "${BOLD}${CYAN}───────────────────────────────${RESET}\n"
  echo -e ""
  echo -e "${BOLD}${CYAN}System Information${RESET}"
  echo "──────────────────────────────────────"
  echo -e "▸ CPU Model          : ${model}"
  echo -e "▸ CPU Cores          : ${cores} @ ${freq} GHz"
  echo -e "▸ CPU Cache          : ${cache}"
  echo -e "▸ AES-NI             : $(color_status "$aes")"
  echo -e "▸ VM-x/AMD-V         : $(color_status "$vmx")"
  echo -e "▸ Virtualization     : ${virt}"
  echo -e "▸ OS                 : ${os}"
  echo -e "▸ Architecture       : ${arch}"
  echo -e "▸ Kernel             : ${kernel}"
  echo -e "▸ TCP CC             : ${tcp_cc}"
  echo -e "▸ Disk Usage         : ${disk}"
  echo -e "▸ Memory Usage       : ${mem}"
  echo -e "▸ System Uptime      : ${uptime}"
  echo -e "▸ Load Average       : ${load}"
  echo -e "▸ Network            : IPv4: $(color_status "$ipv4") | IPv6: $(color_status "$ipv6")"
  echo -e "▸ Organization       : ${org}"
  echo -e "▸ Location           : ${loc}"
  echo
}

disk_bench() {
  echo -e "${BOLD}${CYAN}Disk Benchmark${RESET}"
  echo "──────────────────────────────────────"
  mkdir -p "$WORKDIR"
  local bss=(4k 64k 512k 1m)
  for bs in "${bss[@]}"; do
    out="$WORKDIR/fio-${bs}.json"
    fio --name=bevo --filename="$WORKDIR/fio-testfile" --size="$FIO_SIZE" \
      --ioengine="$FIO_IOENGINE" --direct=1 --bs="$bs" \
      --rw=readwrite --rwmixread=50 --numjobs=1 --runtime="$FIO_RUNTIME" \
      --time_based --group_reporting --output-format=json > "$out" 2>/dev/null || true

    read_iops=$(jq '.jobs[0].read.iops' "$out" 2>/dev/null || echo 0)
    write_iops=$(jq '.jobs[0].write.iops' "$out" 2>/dev/null || echo 0)
    read_bw=$(jq '.jobs[0].read.bw' "$out" 2>/dev/null || echo 0)
    write_bw=$(jq '.jobs[0].write.bw' "$out" 2>/dev/null || echo 0)
    read_bw_h=$(awk "BEGIN{printf \"%.2f\", $read_bw/1024}")
    write_bw_h=$(awk "BEGIN{printf \"%.2f\", $write_bw/1024}")

    printf "▸ %-5s | Read: %6.2f MB/s (%s IOPS) | Write: %6.2f MB/s (%s IOPS)\n" \
      "$bs" "$read_bw_h" "$(num_to_human "$read_iops")" "$write_bw_h" "$(num_to_human "$write_iops")"
  done
  echo
}

net_bench() {
  echo -e "${BOLD}${CYAN}Network Benchmark${RESET}"
  echo "──────────────────────────────────────"
  for entry in "${IPERF_SERVERS[@]}"; do
    IFS=':' read -r prov region host port <<<"$entry"
    ping_ms=$(ping -c1 -W2 "$host" 2>/dev/null | tail -1 | awk -F'/' '{print $5}' 2>/dev/null || echo "N/A")
    jsonf="$WORKDIR/iperf-${prov// /_}-${port}.json"
    iperf3 -c "$host" -p "$port" -f m -t 8 -J > "$jsonf" 2>/dev/null || true

    if [ -s "$jsonf" ]; then
      send_bps=$(jq '.end.sum_sent.bits_per_second // 0' "$jsonf" 2>/dev/null)
      recv_bps=$(jq '.end.sum_received.bits_per_second // 0' "$jsonf" 2>/dev/null)
    else
      send_bps=0; recv_bps=0
    fi

    send_mbps=$(awk "BEGIN{printf \"%.2f\", $send_bps/1000000}")
    recv_mbps=$(awk "BEGIN{printf \"%.2f\", $recv_bps/1000000}")
    send_disp=$(color_speed "$send_mbps")
    recv_disp=$(color_speed "$recv_mbps")
    ping_disp=$(color_ping "$ping_ms")

    printf "▸ %-18s (%-2s) | Send: %b Mbps | Recv: %b Mbps | Ping: %b ms\n" \
      "$prov" "$region" "$send_disp" "$recv_disp" "$ping_disp"
  done
  echo
}

cpu_bench() {
  echo -e "${BOLD}${CYAN}CPU Benchmark${RESET}"
  echo "──────────────────────────────────────"
  sc=$(sysbench cpu --threads=1 --time=10 run | awk -F: '/events per second/ {print $2; exit}' | xargs)
  mc=$(sysbench cpu --threads=$(nproc --all) --time=10 run | awk -F: '/events per second/ {print $2; exit}' | xargs)
  echo -e "▸ Single-Core Performance : ${sc} events/sec"
  echo -e "▸ Multi-Core Performance  : ${mc} events/sec"
  echo
}

clear_bench() {
  clear
}

show_help() {
  cat <<EOF
Usage: $0 [OPTIONS]

Options:
  --skip-cpu       Skip CPU benchmark
  --skip-disk      Skip Disk benchmark
  --skip-network   Skip Network benchmark
  --clear          Clear screen before running benchmarks
  --help           Show this help message
EOF
}

main() {
  check_root
  install_dependencies &> /dev/null
  require_cmds jq fio sysbench iperf3 ping bc awk sed curl
  mkdir -p "$WORKDIR"

  local run_cpu=1 run_disk=1 run_net=1 run_clear=0

  for arg in "$@"; do
    case "$arg" in
      --skip-cpu) run_cpu=0 ;;
      --skip-disk) run_disk=0 ;;
      --skip-network) run_net=0 ;;
      --clear) run_clear=1 ;;
      --help) show_help; return ;;
      *) echo "Unknown option: $arg"; show_help; return ;;
    esac
  done

  ((run_clear)) && clear_bench

  sysinfo
  ((run_cpu)) && cpu_bench
  ((run_disk)) && disk_bench
  ((run_net)) && net_bench

  echo -e "${GREEN}Benchmark completed successfully.${RESET}"
}

main "$@"
