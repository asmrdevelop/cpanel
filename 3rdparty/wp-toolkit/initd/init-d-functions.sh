#!/bin/bash

WPT_BASE_PATH="/usr/local/cpanel/3rdparty/wp-toolkit"
WPT_RUN_PATH="$WPT_BASE_PATH/var/run/"

get_pid_file_path()
{
  local daemon_name="$1"
  echo "$WPT_RUN_PATH/$daemon_name.pid"
}

process_is_running()
{
  local pid="$1"
  kill -0 $pid 2>/dev/null
}

process_stop_soft()
{
  local pid="$1"
  kill $pid 1>/dev/null 2>/dev/null
}

process_stop_hard()
{
  local pid="$1"
  kill -9 $pid 1>/dev/null 2>/dev/null
}

action_print_usage()
{
  local script_path="$1"
  echo "Usage: $script_path {status|start|stop|restart}"
  exit 1
}

action_start()
{
  local daemon_name="$1"
  local daemon_title="$2"

  local pid_file_path=$(get_pid_file_path "$daemon_name")
  if [ -f "$pid_file_path" ]; then
    local pid=$(cat "$pid_file_path")
    if process_is_running "$pid"; then
        echo "$daemon_title is already running, killing it"
        process_stop_hard "$pid"
        rm -f "$pid_file_path"
    fi
  fi

  echo "Starting $daemon_title"
  nohup "$WPT_BASE_PATH/bin/run-script" "$daemon_name.php" 1>/dev/null 2>/dev/null &
  local pid="$!"
  mkdir -p "$WPT_RUN_PATH"
  echo "$pid" > "$pid_file_path"
  echo "$daemon_title has been started"
}

action_stop()
{
  local daemon_name="$1"
  local daemon_title="$2"

  local pid_file_path=`get_pid_file_path "$daemon_name"`

  if [ -f $pid_file_path ]; then
    local pid=`cat $pid_file_path`
    if ! process_is_running "$pid"; then
        echo "$daemon_title is not running (pid file exist)"
        rm -f $pid_file_path
    else
        echo "Stopping $daemon_title (process ID: $pid)"
        process_stop_soft "$pid"
        sleep 5
        if process_is_running "$pid"; then
          process_stop_hard "$pid"
        fi

        if ! process_is_running "$pid"; then
            rm -f $pid_file_path
            echo "$daemon_title has been stopped"
        else
            echo "Failed to stop $daemon_title"
            exit 1
        fi
    fi
  else
    echo "$daemon_title is not running"
  fi
}

action_restart()
{
  local daemon_name="$1"
  local daemon_title="$2"
  action_stop "$daemon_name" "$daemon_title"
  action_start "$daemon_name" "$daemon_title"
}

action_status()
{
  local daemon_name="$1"
  local daemon_title="$2"

  local pid_file_path=`get_pid_file_path "$daemon_name"`

  if [ -f $pid_file_path ]; then
    pid=`cat "$pid_file_path"`
    if ! process_is_running "$pid"; then
        echo "$daemon_title is not running (pid file exists)"
    else
        echo "$daemon_title is running"
    fi
  else
    echo "$daemon_title is not running"
  fi
}

run_init_d_script()
{
    local daemon_name="$1"
    local daemon_title="$2"
    local action="$3"
    local script_path="$4"

    case "$action" in
      status)
        action_status "$daemon_name" "$daemon_title"
      ;;
      start)
        action_start "$daemon_name" "$daemon_title"
      ;;
      stop)
        action_stop "$daemon_name" "$daemon_title"
      ;;
      restart)
        action_restart "$daemon_name" "$daemon_title"
      ;;
      *)
        action_print_usage "$script_path"
    esac
}

