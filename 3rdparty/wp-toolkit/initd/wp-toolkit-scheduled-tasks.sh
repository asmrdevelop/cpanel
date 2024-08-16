#!/bin/bash
#
# wp-toolkit-scheduled-tasks             Startup script for WP Toolkit scheduled tasks service
#
# chkconfig: - 85 15
#
### BEGIN INIT INFO
# Provides: wp-toolkit-scheduled-tasks
# Required-Start: $local_fs $remote_fs $network
# Required-Stop: $local_fs $remote_fs $network
# Default-Start: 2 3 4 5
# Default-Stop: 0 1 6
# Short-Description: WP Toolkit scheduled tasks service
### END INIT INFO

source "/usr/local/cpanel/3rdparty/wp-toolkit/initd/init-d-functions.sh"

script_path="$0"
action="$1"
run_init_d_script "scheduled-tasks-executor" "WP Toolkit scheduled tasks service" "$action" "$script_path"
