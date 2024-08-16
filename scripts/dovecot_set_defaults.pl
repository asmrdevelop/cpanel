#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - scripts/dovecot_set_defaults.pl         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::AdvConfig::dovecot ();

#----------------------------------------------------------------------
# This is here because CPANEL-7779 added the ability of customers to alter
# Dovecot LMTP’s client_limit, but what they probably should have edited was
# the process_limit.
#----------------------------------------------------------------------

my $conf = Cpanel::AdvConfig::dovecot::get_config();

#CPANEL-7779 allows this to be added, but this is the way of
#darkness and despair for LMTP.
delete $conf->{'lmtp_client_limit'};

Cpanel::AdvConfig::dovecot::save_config($conf);

1;
