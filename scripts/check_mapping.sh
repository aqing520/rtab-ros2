#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROS_DISTRO_NAME="${ROS_DISTRO_NAME:-humble}"
WAIT_TIMEOUT_SEC="${WAIT_TIMEOUT_SEC:-3}"

DEMO_BAG_DEFAULT_FILE="$ROOT_DIR/bags/demo_mapping/demo_mapping.db3"
DEMO_BAG_DEFAULT_DIR1="$ROOT_DIR/bags/demo_mapping_bag"
DEMO_BAG_DEFAULT_DIR2="$ROOT_DIR/bags/demo_mapping"

usage() {
  cat <<USAGE
Usage:
  $(basename "$0") demo-up [--gui]
  $(basename "$0") demo-play [bag_path] [--no-loop]
  $(basename "$0") real-up
  $(basename "$0") status

Examples:
  bash scripts/check_mapping.sh demo-up
  bash scripts/check_mapping.sh demo-play
  bash scripts/check_mapping.sh demo-play ~/rtabmap_nav2_stack/bags/demo_mapping/demo_mapping.db3
  bash scripts/check_mapping.sh real-up
  bash scripts/check_mapping.sh status
USAGE
}

source_env() {
  set +u
  source "/opt/ros/${ROS_DISTRO_NAME}/setup.bash"
  source "$ROOT_DIR/install/setup.bash"
  set -u
}

has_topic_data() {
  local topic="$1"
  timeout "${WAIT_TIMEOUT_SEC}s" ros2 topic echo --once "$topic" >/dev/null 2>&1
}

topic_type() {
  local topic="$1"
  ros2 topic type "$topic" 2>/dev/null | tr -d '\r' || true
}

print_status() {
  echo "[INFO] Root       : $ROOT_DIR"
  echo "[INFO] ROS distro : $ROS_DISTRO_NAME"

  echo
  echo "[STEP] Nodes (rtabmap/livox/mock)"
  ros2 node list 2>/dev/null | grep -E 'rtabmap|livox|mock' || true

  echo
  echo "[STEP] Topics (map/info/clock/lidar/odom/scan)"
  ros2 topic list -t 2>/dev/null | grep -Ei '(^/map$|/info$|/clock$|lidar|point|scan|odom|rtabmap)' || true

  echo
  echo "[STEP] Quick topic checks"
  local t
  for t in /clock /map /info /jn0/base_scan /sensors/lidar/points_deskewed /odometry/local; do
    local ty
    ty="$(topic_type "$t")"
    if [[ -z "$ty" ]]; then
      echo "[MISS] $t"
      continue
    fi
    if has_topic_data "$t"; then
      echo "[OK]   $t ($ty)"
    else
      echo "[WAIT] $t ($ty)"
    fi
  done
}

resolve_demo_bag_path() {
  if [[ -n "${1:-}" ]]; then
    echo "$1"
    return 0
  fi

  if [[ -f "$DEMO_BAG_DEFAULT_FILE" ]]; then
    echo "$DEMO_BAG_DEFAULT_FILE"
    return 0
  fi
  if [[ -d "$DEMO_BAG_DEFAULT_DIR1" ]]; then
    echo "$DEMO_BAG_DEFAULT_DIR1"
    return 0
  fi
  if [[ -d "$DEMO_BAG_DEFAULT_DIR2" ]]; then
    echo "$DEMO_BAG_DEFAULT_DIR2"
    return 0
  fi

  echo "$DEMO_BAG_DEFAULT_FILE"
}

run_demo_up() {
  local gui="false"
  if [[ "${1:-}" == "--gui" ]]; then
    gui="true"
  fi

  source_env
  echo "[STEP] Starting demo mapping launch"
  echo "[INFO] GUI=$gui"
  ros2 launch rtabmap_demos robot_mapping_demo.launch.py rviz:="$gui" rtabmap_viz:="$gui"
}

run_demo_play() {
  local bag_path_arg="${1:-}"
  local loop="true"
  if [[ "${2:-}" == "--no-loop" || "${1:-}" == "--no-loop" ]]; then
    loop="false"
    [[ "${1:-}" == "--no-loop" ]] && bag_path_arg=""
  fi

  source_env

  local bag_path
  bag_path="$(resolve_demo_bag_path "$bag_path_arg")"

  if [[ -d "$bag_path" ]]; then
    echo "[STEP] Playing rosbag directory"
    echo "[INFO] path=$bag_path"
    ros2 bag reindex "$bag_path" >/dev/null 2>&1 || true
    ros2 bag info "$bag_path" || true
    if [[ "$loop" == "true" ]]; then
      ros2 bag play "$bag_path" --clock -l
    else
      ros2 bag play "$bag_path" --clock
    fi
    return 0
  fi

  if [[ -f "$bag_path" ]]; then
    echo "[STEP] Playing rosbag sqlite file"
    echo "[INFO] path=$bag_path"
    ros2 bag info -s sqlite3 "$bag_path" || true
    if [[ "$loop" == "true" ]]; then
      ros2 bag play -s sqlite3 "$bag_path" --clock -l
    else
      ros2 bag play -s sqlite3 "$bag_path" --clock
    fi
    return 0
  fi

  echo "[ERROR] Bag path not found: $bag_path" >&2
  echo "[HINT] Provide path manually, e.g.:" >&2
  echo "       bash scripts/check_mapping.sh demo-play ~/rtabmap_nav2_stack/bags/demo_mapping/demo_mapping.db3" >&2
  return 2
}

run_real_up() {
  source_env
  echo "[STEP] Starting real mapping stack"
  exec bash "$ROOT_DIR/scripts/start_all_mapping.sh"
}

main() {
  local cmd="${1:-}"
  case "$cmd" in
    demo-up)
      shift
      run_demo_up "${1:-}"
      ;;
    demo-play)
      shift
      run_demo_play "${1:-}" "${2:-}"
      ;;
    real-up)
      run_real_up
      ;;
    status)
      source_env
      print_status
      ;;
    -h|--help|help|"")
      usage
      ;;
    *)
      echo "[ERROR] Unknown command: $cmd" >&2
      usage
      return 1
      ;;
  esac
}

main "$@"
