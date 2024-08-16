package Cpanel::Async::FlockFile;

# cpanel - Cpanel/Async/FlockFile.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Async::FlockFile

=head1 SYNOPSIS

    my $fh_p = Cpanel::Async::FlockFile::lock_exclusive_p(
        '/path/to/be/locked',
        timeout => 25,
        on_enoent => sub {
            Cpanel::Autodie::mkdir('/path/to/be');
        },
    );

=head1 DESCRIPTION

This module wraps L<Cpanel::Async::Flock> with logic to create or open
a specific path on disk.

=cut

#----------------------------------------------------------------------

use Cpanel::Async::Flock             ();
use Cpanel::Async::FlockFile::Handle ();
use Cpanel::Exception                ();
use Promise::XS                      ();

use Cpanel::Autodie          ();
use Cpanel::Fcntl::Constants ();

use Errno ();    ## PPI NO PARSE - mis-parse

my $_DEFAULT_TIMEOUT = 60;
my $_PERMS           = 0600;

# Exposed for testing:
our $_ROOT_DIR = '/var/cpanel';

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 promise($handle) = lock_exclusive_p( $PATH, %OPTS )

Returns a promise that resolves to a L<Cpanel::Async::FlockFile::Handle>
instance around a new, locked filehandle to $PATH.
$PATH will be created (0600 perms) if it does not exist. $PATH is not
intended to hold content; it’s just a lock that you can use for whatever
purpose.

$PATH B<MUST> reside under F</var/cpanel>. This is because the underlying
lock is attained via F<flock(2)>, which we don’t trust over NFS. We assume
that F</var/cpanel> is a local mount, so that should work. It’s possible
that other paths could work; if there’s need later on we can revisit this
restriction then.

%OPTS are:

=over

=item * C<timeout> - optional, in seconds; defaults to 60. May be 0 to
avoid waiting for the lock.

=item * C<on_enoent> - optional, a callback to run if the attempt
to C<open()> $PATH fails. If this is given, a 2nd attempt is made to
open the path after the callback runs. (This callback will I<not> run
if that 2nd attempt fails.)

This is useful for, e.g., creating the directory where $PATH should
reside.

=back

=cut

sub lock_exclusive_p ( $path, %opts ) {
    return _get_lock_p( 'flock_EX', $path, \%opts );
}

=head2 promise($fh) = lock_shared_p( $PATH, %OPTS )

Same as C<lock_exclusive_p()> but creates a shared lock instead.

=cut

sub lock_shared_p ( $path, %opts ) {
    return _get_lock_p( 'flock_SH', $path, \%opts );
}

sub _get_lock_p ( $locker_fn, $lockpath, $opts_hr ) {

    # This is a sanity-check rather than a proper validation;
    # a real validation would prevent stuff like '/var/cpanel/../blah'.
    if ( 0 != rindex( $lockpath, $_ROOT_DIR, 0 ) ) {
        require Carp;
        Carp::croak("Lock path “$lockpath” is not under $_ROOT_DIR!");
    }

    my $timeout = $opts_hr->{'timeout'} // $_DEFAULT_TIMEOUT;

    my $fh;

    local $@;
    eval { $fh = _open_lockfile( $lockpath, $opts_hr->{'on_enoent'} ) } or do {
        return Promise::XS::rejected($@);
    };

    my $promise = Cpanel::Async::Flock->can($locker_fn)->( $fh, $lockpath, $timeout );

    return $promise->then(
        sub {
            return Cpanel::Async::FlockFile::Handle->new( $fh, $lockpath );
        }
    );
}

sub _open_lockfile ( $lockpath, $on_enoent_cr ) {
    my $fh;

    local $!;

    # NB: We can’t write to this file because it’ll be problematic
    # for the file to exist before its contents are written.
    my $mode = $Cpanel::Fcntl::Constants::O_CREAT | $Cpanel::Fcntl::Constants::O_RDONLY;

    sysopen $fh, $lockpath, $mode, $_PERMS or do {
        if ( $! == Errno::ENOENT && $on_enoent_cr ) {
            $on_enoent_cr->();

            Cpanel::Autodie::sysopen( $fh, $lockpath, $mode, $_PERMS );
        }
        else {
            die Cpanel::Exception::create(
                'IO::FileOpenError',
                [
                    mode  => $mode,
                    path  => $lockpath,
                    error => $!,
                ],
            );
        }
    };

    return $fh;
}

1;
