pod_man_installed() {
    echo "Checking if ${podman_bin} is installed.";
    if [[ -e ${podman_bin} ]]; then
        echo "Podman installed.";
        return 0;  # True
    else
        echo "Podman is not installed.";
        return 1;  # False
    fi
}

pod_exists() {
    local pod=$1;

    set +e # Next command can fail;

    ${podman_bin} pod exists "${pod}";
    FOUND=$?;
    set -e # Restore exit on error
    if [[ $FOUND -eq 0 ]]; then
        echo "podman pod ${pod} exists.";
        return 0;  # True
    else
        echo "podman pod ${pod} does NOT exist.";
        return 1;  # False
    fi
}