package Cpanel::Public::ApacheConf;

# cpanel - Cpanel/Public/ApacheConf.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

######
#NOTE: This is a legacy module and only provided for backwards compat. (jnk)
######

use strict;

use Cpanel::ApacheConf         ();
use Cpanel::ApacheConf::Parser ();

require Exporter;
our @ISA    = qw(Exporter );
our @EXPORT = qw( loadhttpdconf );

*VERSION       = \$Cpanel::ApacheConf::Parser::VERSION;
*loadhttpdconf = \&Cpanel::ApacheConf::loadhttpdconf;

1;
