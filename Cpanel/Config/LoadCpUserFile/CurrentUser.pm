package Cpanel::Config::LoadCpUserFile::CurrentUser;

# cpanel - Cpanel/Config/LoadCpUserFile/CurrentUser.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Config::LoadCpUserFile ();

=encoding utf-8

=head1 NAME

Cpanel::Config::LoadCpUserFile::CurrentUser - Singleton loader for CpUserFile

=head1 SYNOPSIS

    use Cpanel::Config::LoadCpUserFile::CurrentUser;

    Cpanel::Config::LoadCpUserFile::CurrentUser::load('username');

=head1 DESCRIPTION

Prevents double loading of a cPUserFile

Only use for the current logged in user to preserve singleton

=cut

=head2 load

load single instance of cPUserFile

=over 2

=item Input

=over 3

=item C<SCALAR>

    $user - username to load

=back

=item Output

=over 3

=item C<HASHREF>

    Returns singleton of user in question

=back

=back

=cut

my $_cpuser_ref_singleton;
my $_cpuser_user;

sub load {
    my ($user) = @_;
    if ( $_cpuser_user && $_cpuser_user eq $user ) {
        return $_cpuser_ref_singleton;
    }
    $_cpuser_user = $user;
    return ( $_cpuser_ref_singleton = Cpanel::Config::LoadCpUserFile::load($user) );
}

# For testing.
sub _reset {
    $_cpuser_ref_singleton = undef;
    $_cpuser_user          = undef;

    return;
}

1;
