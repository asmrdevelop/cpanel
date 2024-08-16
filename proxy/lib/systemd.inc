service_exists() {
    local name=$1
    if [[ $(systemctl list-units --all -t service --full --no-legend "$name.service" | sed 's/^\s*//g' | cut -f1 -d' ') == $name.service ]]; then
        echo "systemd service ${name}.service exists"
        return 0;  # True
    else
        echo "systemd service ${name}.service does NOT exist"
        return 1;  # False
    fi
}

service_is_active() {
    local name=$1
    systemctl is-active --quiet ${name}.service
    ACTIVE=$?
    if [[ ${ACTIVE} -eq 0 ]]; then
        echo "systemd service ${name}.service is active."
        return 0; # True
    else
        echo "systemd service ${name}.service is NOT active."
        return 1; # False
    fi
}