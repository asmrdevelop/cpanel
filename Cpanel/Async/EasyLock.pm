package Cpanel::Async::EasyLock;

# cpanel - Cpanel/EasyLock.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Async::EasyLock

=head1 SYNOPSIS

    my $p = Cpanel::Async::EasyLock::lock_shared_p('SomeLockName')->then( sub ($fh) {
        # ...
    } );

=head1 DESCRIPTION

This module wraps L<Cpanel::Async::FlockFile> with convenience logic to
store lockfiles in a single place, with a single naming convention.

=cut

#----------------------------------------------------------------------

use Cpanel::Async::FlockFile ();
use Cpanel::Context          ();

our $_BASE;

BEGIN {
    $_BASE = '/var/cpanel/easylock';
}

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 promise($handle) = lock_exclusive_p( $NAME, %OPTS )

Returns a promise that resolves to a L<Cpanel::Async::FlockFile::Handle>
instance around an exclusive-locked filehandle.

%OPTS are:

=over

=item * C<timeout> - As given to L<Cpanel::Async::FlockFile>.

=back

=cut

sub lock_exclusive_p ( $name, %opts ) {
    return _get_lock_p( 'lock_exclusive_p', $name, \%opts );
}

=head2 promise($fh) = lock_shared_p( $NAME, %OPTS )

Same as C<lock_exclusive_p()> but creates a shared lock.

=cut

sub lock_shared_p ( $name, %opts ) {
    return _get_lock_p( 'lock_shared_p', $name, \%opts );
}

#----------------------------------------------------------------------

sub _get_path_for_name ($name) {
    if ( $name =~ tr<\0/><> ) {
        die sprintf "%s: Invalid lock name: %s", __PACKAGE__, $name;
    }

    return "$_BASE/$name";
}

sub _get_lock_p ( $locker_fn, $name, $opts_hr ) {
    Cpanel::Context::must_not_be_void();

    my $lockpath = _get_path_for_name($name);

    return Cpanel::Async::FlockFile->can($locker_fn)->(
        $lockpath,

        %$opts_hr,

        on_enoent => sub {
            require Cpanel::Autodie;
            Cpanel::Autodie::mkdir_if_not_exists( $_BASE, 0700 );
        },
    );
}

1;
