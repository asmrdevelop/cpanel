#cPanel Added Limit Protections -- BEGIN
setenv LIMITUSER $USER
if ( -e /usr/bin/whoami ) then
        setenv LIMITUSER `whoami`
endif
if ( "$LIMITUSER" != "root" ) then
        limit descriptors 100
        limit maxproc 35
        limit memoryuse 200000
        limit datasize 200000
        limit stacksize 8192
        limit coredumpsize 200000
else
        limit descriptors 4096
        limit maxproc 14335
        limit memoryuse unlimited
        limit datasize unlimited
        limit stacksize 8192
        limit coredumpsize 1000000
endif
#cPanel Added Limit Protections -- END

