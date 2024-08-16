package Cpanel::ExitValues::dsync;

# cpanel - Cpanel/ExitValues/dsync.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=pod

=encoding utf-8

=head1 NAME

Cpanel::ExitValues::dsync - exit values utility for the “dsync” utility

=head1 SYNOPSIS

    use Cpanel::ExitValues::dsync ();

    my $dsync_exit = 6;

    if (!Cpanel::ExitValues::dsync->error_is_nonfatal_for_cpanel($dsync_exit)) {
        my $pretty_err = Cpanel::ExitValues::dsync->number_to_string($dsync_exit);
    }

=cut

use strict;

use parent qw(
  Cpanel::ExitValues
);

use Cpanel::Dovecot ();

#These are error codes that cPanel deems not to be error conditions.
#
sub _CPANEL_NONFATAL_ERROR_CODES {
    return qw(0);
}

sub _numbers_to_strings {
    return (
        0                                     => 'Success',
        $Cpanel::Dovecot::DOVEADM_EX_NOTFOUND => 'Host does not exist',
        $Cpanel::Dovecot::DOVEADM_EX_NOUSER   => 'User does not exist',
        $Cpanel::Dovecot::DOVEADM_EX_TEMPFAIL => 'Dovecot offline',
    );
}

1;
