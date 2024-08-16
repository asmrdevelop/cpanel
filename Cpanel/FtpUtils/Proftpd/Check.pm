package Cpanel::FtpUtils::Proftpd::Check;

# cpanel - Cpanel/FtpUtils/Proftpd/Check.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::FindBin         ();
use Cpanel::SafeRun::Object ();

=head1 NAME

Cpanel::FtpUtils::Proftpd::Check

=head1 SYNOPSIS

    my $status_hr = Cpanel::FtpUtils::Proftpd::Check::check_config_by_path(
        '/path/to/config/file',
    );

=head1 DESCRIPTION

Test a ProFTPD configuration file before putting it into action.

=head1 FUNCTIONS

=head2 check_config_by_path( PATH )

Tests a ProFTPD configuration file and returns a hash reference that
represents the result:

=over

=item * C<status> - Boolean to indicate success (1) or failure (0).

=item * C<detail> - Free-text report from the test. Note that
warnings on success are reported here, so B<always> report this field
even when C<status> is truthy. (If there are no warnings or errors, this
field will be an empty string.)

=back

=cut

#overridden in tests
our $_PROFTPD_PATH;

sub check_config_by_path {
    my ($path) = @_;

    die 'Need “path”!' if !$path;

    $_PROFTPD_PATH ||= _get_proftpd_path();

    #NOTE: If it’s ever needed, you can test a buffer by
    #setting $path to '/dev/stdin' and sending the buffer in via “stdin”.
    my $check = Cpanel::SafeRun::Object->new(
        program => $_PROFTPD_PATH,
        args    => [
            '--configtest',
            '--config' => $path,
        ],
    );

    if ( $check->signal_code() ) {
        $check->die_if_error();
    }

    return {
        status => !$check->CHILD_ERROR() ? 1 : 0,
        detail => $check->stderr(),
    };
}

#called from tests
sub _get_proftpd_path {
    return Cpanel::FindBin::findbin('proftpd');
}

1;
