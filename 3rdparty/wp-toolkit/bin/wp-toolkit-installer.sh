#!/usr/bin/env bash

# This script could work in two different modes:
# - installer - default mode, used when script is called without any arguments,
#   or with "--url" and/or with "--version" arguments.
# - repo-config-updater - that mode is used for gradual rollouts of WP Toolkit,
#   the script is switched to it when the "--generate-configs" and optional "--build-path"
#   arguments is found.
CURRENT_MODE="installer"

PRODUCT="WP Toolkit for cPanel"
DEFAULT_REPO_BASE_URL="https://wp-toolkit.plesk.com/cPanel"
PATTERN_HOST_WITH_DEV_BUILDS="wpt-builds"
USER_ID=$(id -u)

REPO_BASE_URL=""
PACKAGE_VERSION=""
WPT_VERSION="latest"
WPT_BUILD=""

if [[ "${USER_ID}" != "0" ]]; then
  echo "Allowed only for root user"
  exit 1
fi

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
    --url)
      REPO_BASE_URL="${2}"
      [ "$#" -ge 2 ] && shift 2 || break
      ;;
    --version)
      PACKAGE_VERSION="${2}"
      IFS=- read WPT_VERSION WPT_BUILD TAIL <<< $PACKAGE_VERSION; WPT_VERSION=${WPT_VERSION:-latest}
      [ "$#" -ge 2 ] && shift 2 || break
      ;;
    --generate-configs)
      CURRENT_MODE="repo-config-updater"
      [ "$#" -ge 1 ] && shift 1 || break
      ;;
    *)
      shift
      ;;
    esac
  done
}

# Sets the value for REPO_BASE_URL variable to default one when it's empty.
fill_repo_base_url_variable() {
  if [[ -z "${REPO_BASE_URL}" ]]; then
    REPO_BASE_URL=${DEFAULT_REPO_BASE_URL}
  fi
}

function import_gpg_keys() {
  if [[ "${OS_NAME}" == "Ubuntu" ]]; then
    # One GPG is used for signing both the WP Toolkit and thirdparty repositories
    (wget -qO - ${REPO_BASE_URL}/wp-toolkit-cpanel.gpg || curl -L ${REPO_BASE_URL}/wp-toolkit-cpanel.gpg) | apt-key add -
    checkExitCode 0 "Unable to import WP Toolkit gpg key."
  else
    echo "Installing GPG ..."
    yum -y install gnupg
    checkExitCode 0 "Failed to install gnupg package, see installation log above"

    # Thirdparties are signed with Plesk GPG
    rpm --import ${REPO_BASE_URL}/plesk.gpg
    checkExitCode 0 "Unable to import plesk gpg key."

    # WP Toolkit are signed with own GPG
    rpm --import ${REPO_BASE_URL}/wp-toolkit-cpanel.gpg
    checkExitCode 0 "Unable to import WP Toolkit gpg key."
  fi
}

function create_apt_sources_list() {
  echo "Creating APT Repository sources list ..."
  cat <<EOF >/etc/apt/sources.list.d/wp-toolkit-cpanel.list
# WP Toolkit
deb ${REPO_BASE_URL}/${OS_NAME}-${OS_VERSION}-x86_64/${WPT_VERSION}/wp-toolkit/ ./

# WP Toolkit Thirdparties
deb ${REPO_BASE_URL}/${OS_NAME}-${OS_VERSION}-x86_64/${WPT_VERSION}/thirdparty/ ./
EOF
}

function create_yum_repo_config() {
  if [[ "${OS_NAME}" == "CentOS" && "${OS_VERSION}" == 6 ]]; then
    GPGCHECK_THIRDPARTY=0
  else
    GPGCHECK_THIRDPARTY=1
  fi

  echo "Creating YUM Repository configuration file ..."
  cat <<EOF >/etc/yum.repos.d/wp-toolkit-cpanel.repo
[wp-toolkit-cpanel]
name=WP Toolkit for cPanel
baseurl=${REPO_BASE_URL}/${OS_NAME}-${OS_VERSION}-x86_64/${WPT_VERSION}/wp-toolkit/
enabled=1
gpgcheck=1

[wp-toolkit-thirdparties]
name=WP Toolkit third parties
baseurl=${REPO_BASE_URL}/${OS_NAME}-${OS_VERSION}-x86_64/${WPT_VERSION}/thirdparty/
enabled=1
gpgcheck=${GPGCHECK_THIRDPARTY}
EOF
}

function create_repo_config() {
  if [[ "${OS_NAME}" == "Ubuntu" ]]; then
    create_apt_sources_list
  else
    create_yum_repo_config
  fi
}

function clean_repo_cache() {
  if [[ "${OS_NAME}" == "Ubuntu" ]]; then
    DEBIAN_FRONTEND=noninteractive LANG=C apt-get update
  else
    yum clean all --disablerepo="*" --enablerepo=wp-toolkit-cpanel --enablerepo=wp-toolkit-thirdparties
  fi
}

function exitWithError() {
  echo "ERROR: $*" >&2
  exit 1
}

function checkExitCode() {
  if [ $? -ne "$1" ]; then
    exitWithError "$2"
  fi
}

function detect_os() {
  echo "Detecting OS type and version ..."

  if [ -e /etc/os-release ]; then
    source /etc/os-release

    DIST_ID="${ID}"
    OS_VERSION="${VERSION_ID}"
  elif [ $(which lsb_release 2>/dev/null) ]; then
    DIST_ID="$(lsb_release -s -i)"
    OS_VERSION="$(lsb_release -s -r)"
  elif [ -e /etc/redhat-release ]; then
    DIST_ID="$(cat /etc/redhat-release | sed -n -e 's/\([[:alnum:]]*\)[[:space:]].*/\1/p')"
    OS_VERSION="$(cat /etc/redhat-release | sed -n -e 's/[^0-9]*\([0-9\.]\+\).*/\1/p')"
  elif [ -e /etc/issue ]; then
    DIST_ID="$(cat /etc/issue | sed -n -e 's/\([[:alnum:]]*\)[[:space:]].*/\1/p')"
    OS_VERSION="$(cat /etc/issue | sed -n -e 's/[^0-9]*\([0-9\.]\+\).*/\1/p')"
  fi

  if [ ! -z "${DIST_ID}" ]; then
    DIST_ID="$(echo ${DIST_ID} | tr '[:upper:]' '[:lower:]')"
  fi

  case "$DIST_ID" in
  redhat*)
    # We use the same RPMs for RedHat as for CentOS
    OS_NAME="CentOS"
    ;;
  centos)
    OS_NAME="CentOS"
    ;;
  rhel | cloudlinux | cloudlinuxserver | almalinux | rocky)
    # We use the same RPMs for RHEL, CloudLinux, AlmaLinux and RockyLinux as for CentOS
    OS_NAME="CentOS"
    ;;
  ubuntu)
    OS_NAME="Ubuntu"
    ;;
  *)
    OS_NAME="${DIST_ID}"
    ;;
  esac
}

function check_supported_os_and_version() {
  if [ -z "${OS_NAME}" ]; then
    exitWithError "Cannot determine OS name"
  fi

  if [ "${OS_NAME}" != "CentOS" ] && [ "${OS_NAME}" != "Ubuntu" ]; then
    exitWithError "Only CentOS based distribution and Ubuntu are supported at the moment"
  fi

  if [ "${OS_NAME}" == "Ubuntu" ]; then
    # In Ubuntu take two parts of OS_VERSION, e.g. for "Ubuntu 20.04.2 LTS" we consider OS_VERSION=20.04
    OS_VERSION=$(echo "$OS_VERSION" | sed -n -e 's/\([0-9]\+\.[0-9]\+\).*/\1/p')

    if [ "${OS_VERSION}" != "20.04" ] && [ "${OS_VERSION}" != "22.04" ]; then
      exitWithError "Only Ubuntu 20.04 and 22.04 are supported at the moment"
    fi
  else
    # In CentOS based OS take only first part of OS_VERSION, e.g. for CloudLinux 7.7 we consider OS_VERSION=7
    OS_VERSION=$(echo "$OS_VERSION" | sed -n -e 's/\([0-9]\+\).*/\1/p')

    if [ "${OS_VERSION}" -lt 6 ] || [ "${OS_VERSION}" -gt 9 ]; then
      exitWithError "Only CentOS/CloudLinux 6, 7, 8 and 9 are supported at the moment"
    fi
  fi
}

function install_wp_toolkit_cpanel() {
  # The option for Dpkg is required in case when some configs are left on the server
  # from previous versions of package.
  # Installation of WP Toolkit package always should overwrite configs,
  # this allow to deliver fixes for these files without manual actions from server' admins.

  if [ -z "${WPT_BUILD}" ]; then
    echo "Installing WP Toolkit ..."

    if [[ "${OS_NAME}" == "Ubuntu" ]]; then
      apt-get install -o Dpkg::Options::="--force-confnew" -y wp-toolkit-cpanel
    else
      yum install -y wp-toolkit-cpanel
    fi
  else
    echo "Installing WP Toolkit with version ${PACKAGE_VERSION}..."

    if [[ "${OS_NAME}" == "Ubuntu" ]]; then
      apt-get install -o Dpkg::Options::="--force-confnew" -y "wp-toolkit-cpanel=${PACKAGE_VERSION}*"
    else
      yum install -y "wp-toolkit-cpanel-${PACKAGE_VERSION}"
    fi
  fi

  checkExitCode 0 "Failed to install wp-toolkit-cpanel, see installation log above"
}

parse_args "$@"

if [ "${CURRENT_MODE}" == "installer" ]; then
  fill_repo_base_url_variable

  # The installer script defines the default URL to the host with repositories and you can
  # override it in "--url" argument during installation process. For example, to install specific
  # version which isn't yet delivered to all servers you can use installer as following:
  # "./installer.sh --url https://wp-toolkit.plesk.com/cPanel/build-X.Y.Z".
  #
  # The same version of installer script is used for development purposes and it's required
  # to override the default URL to the host with repositories in such case, both when installer works
  # in "installer" mode and in "repo-config-updater" mode.
  # When the passed value for "--url" argument matches specific pattern, then the
  # file "/root/.wp-toolkit-installer-config-for-development-purposes" is created and used
  # in "repo-config-updater" mode.
  # Mentioned file shouldn't be used on production environments, because if it contain
  # incorrect URL to the host with repositories, then the receiving of updates can broke.
  if [[ "${REPO_BASE_URL}" == *"${PATTERN_HOST_WITH_DEV_BUILDS}"* ]]; then
    cat <<EOF >/root/.wp-toolkit-installer-config-for-development-purposes
REPO_BASE_URL=${REPO_BASE_URL}
EOF
  else
    rm -f /root/.wp-toolkit-installer-config-for-development-purposes
  fi

  detect_os
  check_supported_os_and_version
  create_repo_config
  import_gpg_keys
  clean_repo_cache
  install_wp_toolkit_cpanel
else
  # When the installer script is working as "repo-config-updater" it's possible to override
  # the repo base URL to the host with repositories.
  # This allowed only for development purposes and the file with override is removed
  # when the value doesn't match specific pattern. That's required to avoid possible
  # problems with updates on production environments.
  if [ -e /root/.wp-toolkit-installer-config-for-development-purposes ]; then
    source /root/.wp-toolkit-installer-config-for-development-purposes

    if [[ -n "${REPO_BASE_URL}" && "${REPO_BASE_URL}" != *"${PATTERN_HOST_WITH_DEV_BUILDS}"* ]]; then
      rm -f /root/.wp-toolkit-installer-config-for-development-purposes
      REPO_BASE_URL=""
    fi
  fi

  fill_repo_base_url_variable
  detect_os
  check_supported_os_and_version
  create_repo_config
  clean_repo_cache
fi
