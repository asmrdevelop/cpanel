#!/usr/bin/env bash

WP_TOOLKIT_BASE_NAME="wp-toolkit"
WP_TOOLKIT_BASE_PATH="/usr/local/cpanel/3rdparty/${WP_TOOLKIT_BASE_NAME}"

### Install WHM plugin
installWhmPlugin()
{
    WHM_PLUGIN_NAME="wp-toolkit"
    WHM_BASE_PATH="${WP_TOOLKIT_BASE_PATH}/whm-plugin"

    echo "Install WHM Plugin"

    # Register the plugin with AppConfig.
    /usr/local/cpanel/bin/register_appconfig ${WHM_BASE_PATH}/whm-wp-toolkit.conf
}

### Install customer's plugin
installCpanelPlugin()
{
    CPANEL_PLUGIN_NAME="wp-toolkit"
    CPANEL_PLUGIN_BASE_PATH="${WP_TOOLKIT_BASE_PATH}/cpanel-plugin"
    CPANEL_FRONTEND_PATH="/usr/local/cpanel/base/frontend"

    find ${CPANEL_FRONTEND_PATH} -mindepth 1 -maxdepth 1 -type d -printf "%f\n" | while IFS=$'\n' read -r theme
    do
        CPANEL_PLUGIN_TARGET_PATH="${CPANEL_FRONTEND_PATH}/$theme/${CPANEL_PLUGIN_NAME}"
        echo "Install cPanel Plugin for theme $theme"
        ln -snf ${CPANEL_PLUGIN_BASE_PATH} ${CPANEL_PLUGIN_TARGET_PATH}
        /usr/local/cpanel/scripts/install_plugin --theme "$theme" ${CPANEL_PLUGIN_BASE_PATH}
    done
}

enableCpanelFpmDaemons()
{
  rm -f /etc/cpanel_php_fpmdisable
  /usr/local/cpanel/bin/whmapi1 configureservice service=cpanel_php_fpm enabled=1 monitored=1
  /usr/local/cpanel/scripts/restartsrv cpanel_php_fpm
}

integrateFpmApplication()
{
  # Make symlink to a UNIX socket for cPanel/WHM FPM manager
  mkdir -p /var/cpanel/php-fpm/wp-toolkit
  cd /var/cpanel/php-fpm/wp-toolkit &&  ln -snf /var/run/sw-engine.sock sock

  # cPanel: serve WPT "htdocs" by FPM daemon
  cd /usr/local/cpanel/base/3rdparty &&  ln -snf "${WP_TOOLKIT_BASE_PATH}/htdocs" wpt
  /usr/local/cpanel/bin/register_appconfig "${WP_TOOLKIT_BASE_PATH}/cpanel-plugin/cpanel-wp-toolkit.conf"

  # WHM: serve WPT "htdocs" by FPM daemon
  cd /usr/local/cpanel/whostmgr/docroot/cgi && ln -snf "${WP_TOOLKIT_BASE_PATH}/htdocs" wpt
  /usr/local/cpanel/bin/register_appconfig "${WP_TOOLKIT_BASE_PATH}/whm-plugin/whm-wp-toolkit-api.conf"
}

startEngines()
{
  if [ -x /bin/systemctl ]; then
    # CentOS > 7, CloudLinux > 7: services are managed by systemd

    # enable sw-engine services
    /bin/systemctl enable sw-engine.service
    # restart sw-engine service
    /bin/systemctl restart sw-engine
  else
    # CentOS 6, CloudLinux 6: services are managed in old init.d way

    # Restart sw-engine in a special way: when you simply run "/etc/init.d/sw-engine restart", it hangs
    # (sw-engine process seems to get started in foreground and keeps running and accepting connections,
    # making the installation script to hang; root cause of that strange behavior is not clear and requires
    # additional complex investigation)
    nohup /etc/init.d/sw-engine restart 1>/dev/null 2>/dev/null &
  fi
}

installServices()
{
  echo "Install services"

  # Unclear is reload required or not
  if [ -x /bin/systemctl ]; then
    /bin/systemctl daemon-reload
  fi

  for service in background-tasks scheduled-tasks; do
    if [ -x /bin/systemctl ]; then
      # CentOS > 7, CloudLinux > 7: services are managed by systemd
      /bin/systemctl is-enabled "wp-toolkit-${service}" || /bin/systemctl enable "wp-toolkit-${service}"
      /bin/systemctl restart "wp-toolkit-${service}"
    else
      # CentOS 6, CloudLinux 6: services are managed in old init.d way

      # We copy scripts at runtime to:
      # 1) keep the same RPM for all OSes
      # 2) avoid any possible issues with symlinks (it is not confirmed that chkconfig completely supports them)
      # and hardlinks (we can't guarantee that /usr and /etc are on the same disk)
      # As a disadvantage, you won't see that /etc/init.d/wp-toolkit-* files are from WP Toolkit RPM package
      cp -af "/usr/local/cpanel/3rdparty/wp-toolkit/initd/wp-toolkit-${service}.sh" "/etc/init.d/wp-toolkit-${service}"
      chkconfig --add "wp-toolkit-${service}"
      /etc/init.d/wp-toolkit-${service} start
    fi
  done
}

### Run post-install script: initialize database, initialize maintenance tasks, connect server, etc
runPostInstall()
{
    echo "Perform initial settings"
    if [ -z "${PREVIOUS_PACKAGE_VERSION}" ]; then
      "$WP_TOOLKIT_BASE_PATH/bin/run-script" post-install.php
    else
      "$WP_TOOLKIT_BASE_PATH/bin/run-script" post-install.php upgrade ${PREVIOUS_PACKAGE_VERSION}
    fi
}

### Fetch Leika config
fetchLeikaConfig()
{
    echo "Fetch leika config"
    "$WP_TOOLKIT_BASE_PATH/bin/wpt-cli.sh" update-leika-config
}

enablePhpForResellers()
{
  /usr/sbin/whmapi1 set_tweaksetting key=disable-php-as-reseller-security value=1
  # the previous command could fail due to absent cPanel license:
  # set value by manual file edit as fallback
  sed -i 's/disable-php-as-reseller-security=0/disable-php-as-reseller-security=1/' /var/cpanel/cpanel.config
}

disableSwCpServer()
{
  # sw-cp-server has been used in previous integration schema, it is not necessary anymore and should be removed
  # run that in background as starting RPM withing RPM script causes deadlock
  nohup rpm -e sw-cp-server 1>/dev/null 2>/dev/null &
}

removeSwKeyStorage()
{
  # sw/key/storage has been used in previous licensing schema, it is not necessary anymore and should be removed
  # run that in background as starting RPM withing RPM script causes deadlock
  nohup rm -rf /etc/sw 1>/dev/null 2>/dev/null &
}

renameWpToolkitFeature()
{
  featureFile="/usr/local/cpanel/whostmgr/addonfeatures/wp-toolkit"
  if [ -f $featureFile ]; then
    sed -i 's/WordPress/WP/' $featureFile
  fi
}

addHostingPlanExtension()
{
  # Add hosting plan extension for WP Toolkit

  # grep all hosting plans from listpkgs
  # and add extension for each plan
  /usr/local/cpanel/bin/whmapi1 listpkgs | grep -oP 'name: \K\w+' | while read -r plan; do
    /usr/local/cpanel/bin/whmapi1 addpkgext _PACKAGE_EXTENSIONS=wp-toolkit name=$plan
  done
}

enableCpanelFpmDaemons
startEngines
installWhmPlugin
installCpanelPlugin
integrateFpmApplication
runPostInstall
installServices
fetchLeikaConfig
enablePhpForResellers
disableSwCpServer
removeSwKeyStorage
renameWpToolkitFeature
addHostingPlanExtension
