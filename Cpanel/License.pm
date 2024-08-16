package Cpanel::License;

# cpanel - Cpanel/License.pm               Copyright 2022 cPanel L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Server::Type::Users ();
use Cpanel::SafeRun::Object     ();

=encoding utf-8

=head1 NAME

Cpanel::License - Check to see if the system has a license

=head1 SYNOPSIS

    use Cpanel::License;

    Cpanel::License::is_licensed();
    Cpanel::License::is_licensed(skip_max_user_check => 1);

=head1 DESCRIPTION

Check to see if the system has a license. Includes user count checks by default,
but they may be disabled using the skip_max_user_check parameter.

=cut

sub is_licensed {
    my %args = @_;

    my ($cplisc_mtime) = ( stat('/usr/local/cpanel/cpanel.lisc') )[9];
    return 0 unless $cplisc_mtime;

    # Determine if the license is invalid.
    my $run = Cpanel::SafeRun::Object->new( 'program' => '/usr/local/cpanel/cpanel', args => ['-F'] );

    # If cpanel exits non-zero then it is a good indicator the license is bad.
    return 0 if $run->CHILD_ERROR();

    return 0 if !$args{skip_max_user_check} && Cpanel::Server::Type::Users::max_users_exceeded();

    my ($licensecfg_mtime) = ( stat('/var/cpanel/license.cfg') )[9];

    # refresh the license when producttypes changed
    if ( $licensecfg_mtime && $licensecfg_mtime >= $cplisc_mtime ) {
        return 0;
    }

    return 1;
}

1;
