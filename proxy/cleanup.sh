#!/usr/bin/env bash

set -e           # Exit on error
set -o nounset   # No unset variables
if [[ "${TRACE-0}" == "1" ]]; then set -o xtrace; fi

dir_path=$(dirname "$0")

# Check if we should run the script based on feature checking
# shellcheck source=/usr/local/cpanel/proxy/lib/preconditions.inc
source "${dir_path}/lib/preconditions.inc"

# shellcheck source=/usr/local/cpanel/proxy/config.inc
source "${dir_path}/config.inc"
# shellcheck source=/usr/local/cpanel/proxy/lib/draw.inc
source "${dir_path}/lib/draw.inc"
# shellcheck source=/usr/local/cpanel/proxy/lib/systemd.inc
source "${dir_path}/lib/systemd.inc"
# shellcheck source=/usr/local/cpanel/proxy/lib/podman.inc
source "${dir_path}/lib/podman.inc"

need_cpsrvd_restart=0

echo -n "$GREEN" && draw_line 60 && echo -n "$RESET";
echo "Cleaning up the cPanel proxy if present from other branch.";
echo -n "$GREEN" && draw_line 60 && echo -n "$RESET";

if service_exists "${pod_unit}"; then
    if service_is_active "${pod_unit}"; then
        echo 'Stopping the cPanel proxy systemd service.';
        systemctl --force kill "${pod_unit}";
        systemctl --force stop "${pod_unit}";
        need_cpsrvd_restart=1;
    fi
    systemctl disable "${pod_unit}";
    systemctl daemon-reload
    systemctl reset-failed
fi

if pod_man_installed; then
    if pod_exists "${pod_name}"; then
        echo "Removing the Pod ${pod_name}.";

        # This sometimes reports fail even though it completes successfully
        # To keep these out of the log, we are just redirecting STDERR to
        # /dev/null. If the podman pod exists, the rm command will alwasy succeed.
        ${podman_bin} pod rm --force "${pod_name}" 2>/dev/null;
        need_cpsrvd_restart=1;
    fi
fi

if [ "${need_cpsrvd_restart}" == 1 ]; then
    echo "Restarting cpsrvd";
    service cpanel restart;
fi
