#cPanel Added Limit Protections -- BEGIN

#unlimit so we can run the whoami
ulimit -n 4096 -u 14335 -m unlimited -d unlimited -s 8192 -c 1000000 -v unlimited 2>/dev/null

LIMITUSER=$USER
if [ -e "/usr/bin/whoami" ]; then
    LIMITUSER=$(/usr/bin/whoami)
fi

# Limit the user only if we are not root and are a regular user (UID greater
# than or equal to UID_MIN).
if [ "$LIMITUSER" != "root" ] &&
    ! id -Gn | grep -qsP '(^| )(wheel|sudo)( |$)' &&
    [ "$(id -u)" -ge "$( (grep -s '^UID_MIN' /etc/login.defs || echo 'x 500') | awk '{print $2}')" ]
then
    ulimit -n 100 -u 35 -m 200000 -d 200000 -s 8192 -c 200000 -v unlimited 2>/dev/null
else
    ulimit -n 4096 -u 14335 -m unlimited -d unlimited -s 8192 -c 1000000 -v unlimited 2>/dev/null
fi
#cPanel Added Limit Protections -- END
