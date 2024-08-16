PHP_ARG_ENABLE(homeloader, whether to enable Home Loader support,
        [ --enable-homeloader   Enable Home Loader support])

    if test "$PHP_HOMELOADER" = "yes"; then
    AC_DEFINE(HAVE_HOMELOADER, 1, [Whether you have Home Loader])
PHP_NEW_EXTENSION(homeloader, homeloader.c, $ext_shared)
    fi
