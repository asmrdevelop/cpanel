package Cpanel::Rlimit::Unset;

# cpanel - Cpanel/Rlimit/Unset.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Sys::Rlimit ();
use Cpanel::Rlimit      ();

=encoding utf-8

=head1 NAME

Cpanel::Rlimit::Unset - Unset rlimits before starting a service or system from cron.

=head1 SYNOPSIS

    use Cpanel::Rlimit::Unset;

    Cpanel::Rlimit::Unset::unset_rlimits();

=head1 DESCRIPTION

This module takes care of setting rlimits to sane values in order to keep
cPanel daemons and services running in an expected environment.

This module only interacts with the most relevant rlimits; it doesn’t
do anything with, for example, RLIMIT_MSGQUEUE. See L<Cpanel::Sys::Rlimit>
for more details on the implementation.

=head2 unset_rlimits()

Remove or set rlimits to infinity.

Any failures prompt a warning. Nothing is returned.

=cut

sub unset_rlimits {

    local $@;

    eval {
        no warnings 'once';

        my $infinity = $Cpanel::Sys::Rlimit::RLIM_INFINITY;
        foreach my $limit ( sort keys %Cpanel::Sys::Rlimit::RLIMITS ) {
            next if $limit eq 'NOFILE';    # handled by set_open_files_to_maximum since
                                           # it was trying to raise the limit past what
                                           # the kernel allowed and ended up doing
                                           # nothing. see CPANEL-11426
            next if $limit eq 'AS';        # handled by set_rlimit_to_infinity
            next if $limit eq 'RSS';       # handled by set_rlimit_to_infinity
            next if $limit eq 'CORE';      # handled by set_rlimit_to_infinity
            local $@;
            eval { Cpanel::Sys::Rlimit::setrlimit( $limit, $infinity, $infinity ) };
            warn if $@;
        }

        Cpanel::Rlimit::set_open_files_to_maximum();
        Cpanel::Rlimit::set_rlimit_to_infinity();
    };

    warn if $@;

    return;
}

1;
