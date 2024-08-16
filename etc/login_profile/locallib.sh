#cPanel Added local::lib -- BEGIN
LOCALLIBUSER=$USER
if [ -e "/usr/bin/whoami" ]; then
    LOCALLIBUSER="$(/usr/bin/whoami)"
fi
if [ "$LOCALLIBUSER" != "root" -a -e "/var/cpanel/users/$LOCALLIBUSER" ]; then
    eval $(perl -Mlocal::lib >/dev/null 2>&1)
fi
#cPanel Added local::lib -- END
