#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=packaging/linux/lib.sh
source "$script_dir/lib.sh"

test "$#" -eq 3 || die 'usage: verify_installed_app.sh LAUNCHER APP_ROOT native|appimage'
launcher=$1
app_root=$2
verification_mode=$3
case "$verification_mode" in
  native|appimage) ;;
  *) die "unknown verification mode: $verification_mode" ;;
esac
require_file "$launcher"
validate_bundle_shape "$app_root"
for command in dbus-run-session readelf xdotool Xvfb; do
  require_command "$command"
done
test "$EUID" -ne 0 || die 'installed application verification must run as an ordinary user'

if test "$verification_mode" = appimage; then
  appdir=$(cd -- "$(dirname -- "$launcher")" && pwd)
  app_lib="$app_root/lib"
  portable_lib="$appdir/usr/lib"
  multiarch_lib="$appdir/usr/lib/x86_64-linux-gnu"
  export LD_LIBRARY_PATH="${app_lib}:${multiarch_lib}:${portable_lib}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
fi

if test "$verification_mode" = native; then
  require_command gst-inspect-1.0
  gst-inspect-1.0 playbin >/dev/null
  gst-inspect-1.0 audioconvert >/dev/null
  gst-inspect-1.0 autoaudiosink >/dev/null
  gst-inspect-1.0 souphttpsrc >/dev/null
  for helper in gst-plugin-scanner WebKitWebProcess WebKitNetworkProcess; do
    find /usr/lib /usr/lib64 /usr/libexec -type f -name "$helper" \
      -print -quit 2>/dev/null | grep -q . || \
      die "installed runtime is missing $helper"
  done
fi
ldd "$app_root/lib/libmedia_kit_video_plugin.so" | grep -q 'libmpv.so.2'
ldd "$app_root/lib/libwebview_all_linux_plugin.so" | grep -q 'libwebkit2gtk-4.1.so.0'
ldd "$app_root/lib/libflutter_secure_storage_linux_plugin.so" | grep -q 'libsecret-1.so.0'

smoke_directory=$(mktemp -d /tmp/flutterustmusic-installed-smoke-XXXXXX)
trap 'rm -rf -- "$smoke_directory"' EXIT
verification_home=${FURA_VERIFY_HOME:-"$smoke_directory/home"}
mkdir -p "$verification_home" "$smoke_directory/cwd with spaces"
log_file="$smoke_directory/application.log"

export launcher app_root smoke_directory verification_home log_file
# Exported variables expand in the isolated child shell.
# shellcheck disable=SC2016
dbus-run-session -- bash -eu -o pipefail -c '
  export HOME="$verification_home"
  export XDG_CONFIG_HOME="$HOME/.config"
  export XDG_CACHE_HOME="$HOME/.cache"
  export XDG_DATA_HOME="$HOME/.local/share"
  export LIBGL_ALWAYS_SOFTWARE=1
  mkdir -p "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME"
  cd "$smoke_directory/cwd with spaces"

  app_pid=""
  xvfb_pid=""
  cleanup() {
    if test -n "$app_pid" && kill -0 "$app_pid" 2>/dev/null; then
      kill -TERM "$app_pid" 2>/dev/null || true
      wait "$app_pid" 2>/dev/null || true
    fi
    if test -n "$xvfb_pid" && kill -0 "$xvfb_pid" 2>/dev/null; then
      kill -TERM "$xvfb_pid" 2>/dev/null || true
      wait "$xvfb_pid" 2>/dev/null || true
    fi
  }
  trap cleanup EXIT INT TERM

  export DISPLAY=:$((90 + ($$ % 900)))
  xvfb_log="$smoke_directory/xvfb.log"
  Xvfb "$DISPLAY" -screen 0 1280x800x24 -nolisten tcp -ac \
    >"$xvfb_log" 2>&1 &
  xvfb_pid=$!
  display_ready=false
  for _ in {1..50}; do
    if ! kill -0 "$xvfb_pid" 2>/dev/null; then
      printf "Xvfb exited before accepting clients\n" >&2
      cat "$xvfb_log" >&2
      exit 1
    fi
    if xdotool getmouselocation >/dev/null 2>&1; then
      display_ready=true
      break
    fi
    sleep 0.1
  done
  if test "$display_ready" != true; then
    printf "Xvfb did not accept clients within five seconds\n" >&2
    cat "$xvfb_log" >&2
    exit 1
  fi

  "$launcher" >"$log_file" 2>&1 &
  app_pid=$!
  pid_belongs_to_application() {
    local current_pid=$1
    local status_file
    while [[ "$current_pid" =~ ^[0-9]+$ ]] && test "$current_pid" -gt 1; do
      if test "$current_pid" -eq "$app_pid"; then
        return 0
      fi
      status_file="/proc/$current_pid/status"
      test -r "$status_file" || return 1
      current_pid=$(awk "/^PPid:/ { print \$2; exit }" "$status_file")
    done
    return 1
  }
  found_window=false
  for _ in $(seq 1 30); do
    if ! kill -0 "$app_pid" 2>/dev/null; then
      wait "$app_pid" || true
      printf "application exited before creating a window\n" >&2
      cat "$log_file" >&2
      exit 1
    fi
    while IFS= read -r window_id; do
      window_pid=$(xdotool getwindowpid "$window_id" 2>/dev/null || true)
      if test -n "$window_pid" && pid_belongs_to_application "$window_pid"; then
        found_window=true
        break
      fi
    done < <(xdotool search --onlyvisible --name ".*" 2>/dev/null || true)
    test "$found_window" = true && break
    sleep 1
  done
  if test "$found_window" != true; then
    printf "application did not create an X11 window within 30 seconds\n" >&2
    cat "$log_file" >&2
    kill -TERM "$app_pid" 2>/dev/null || true
    wait "$app_pid" || true
    exit 1
  fi
  kill -TERM "$app_pid"
  wait_status=0
  wait "$app_pid" || wait_status=$?
  app_pid=""
  test "$wait_status" -eq 0 || test "$wait_status" -eq 143
'

if grep -Eqi 'lib[^ ]+\.so[^ ]*: cannot open shared object|error while loading shared libraries|Failed to load dynamic library' \
  "$log_file"; then
  cat "$log_file" >&2
  die 'installed application logged a missing dynamic library'
fi
