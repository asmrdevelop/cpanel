package Cpanel::RestartSrv::Script;

# cpanel - Cpanel/RestartSrv/Script.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

our $SCRIPT_BASE = '/usr/local/cpanel/scripts/restartsrv_';

sub get_restart_script {
    my $service = shift;

    return unless defined $service;

    $service =~ tr{-}{_};    # cpanel-dovecot-solr -> cpanel_dovecot_solr

    my $restart_script = $SCRIPT_BASE . $service;

    return $restart_script if -x $restart_script;
    return;
}

sub can_use_status_code_for_service {
    my $service = shift;

    return 0 unless defined $service;

    my $restart_script = get_restart_script($service);

    # all these symlinks use the ServiceManager framework
    return 1 if $restart_script && -l $restart_script;

    # scripts which are not symlinks but use the ServiceManager framework
    return 1 if grep { $service eq $_ } qw/imap bind ftpd ftpserver named nameserver postgres/;

    return 0;
}

1;
