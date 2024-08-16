# cpanel - bin/packman.py                          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

# This is slightly inefficient. See https://webpros.atlassian.net/browse/ZC-7054

try:
    import yum
    from packman_lib.yum_impl import *
except ImportError:
    from packman_lib.dnf_impl import *
