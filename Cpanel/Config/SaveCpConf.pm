package Cpanel::Config::SaveCpConf;

# cpanel - Cpanel/Config/SaveCpConf.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

sub header_message {
    return <<EOM;
############################## NOTICE #########################################
#                                                                             #
# Manually modifying this file is not recommended!                            #
#                                                                             #
# You should use the interface in WHM > Server Configuration > Tweak Settings #
# for applying changes to these settings.                                     #
#                                                                             #
# https://go.cpanel.net/whmdocsTweakSettings                                  #
#                                                                             #
# For automation tools, you can use the set_tweaksetting WHM API 1 function   #
# to apply changes to individual settings.                                    #
#                                                                             #
# https://go.cpanel.net/set_tweaksetting                                      #
#                                                                             #
###############################################################################
EOM
}

1;
