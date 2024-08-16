#cPanel Added local::lib -- BEGIN
setenv LOCALLIBUSER $USER
if ( -e /usr/bin/whoami ) then
        setenv LOCALLIBUSER `whoami`
endif
if ( "$LOCALLIBUSER" != "root" ) then
    eval $(perl -Mlocal::lib)
endif
#cPanel Added local::lib -- END
