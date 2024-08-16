package Cpanel::Async::UserLock;

# cpanel - Cpanel/Async/UserLock.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Async::UserLock

=head1 SYNOPSIS

    Cpanel::Async::UserLock::create_shared('johnny')->then(
        sub ($lock_handle) {
            # … do something with “johnny”
        }
    );

Handy copy-paste for synchronous contexts:

    my $exists_lock = Cpanel::PromiseUtils::wait_anyevent(
        Cpanel::Async::UserLock::create_shared($username),
    )->get();

=head1 DESCRIPTION

This module implements a generic per-user lock. It’s useful for preventing
account deletion while an operation on that user is in progress.

=head1 USER EXISTENCE REQUIREMENT

This per-user lock depends on the user’s existence; if you try to create
one for a nonexistent user the promise will reject with a
L<Cpanel::Exception::UserNotFound> instance. (The promise could
also reject for other reasons, of course.)

=cut

#----------------------------------------------------------------------

use Errno ();

use Promise::XS ();

use Cpanel::Async::FlockFile            ();
use Cpanel::Config::userdata::Constants ();
use Cpanel::Exception                   ();

use constant _DEFAULT_TIMEOUT => 60;

#----------------------------------------------------------------------

=head1 METHODS

=head2 promise($handle) = create_shared( $USERNAME [, $TIMEOUT ] )

Creates a promise that resolves to a L<Cpanel::Async::FlockFile::Handle>
instance once a shared lock for $USERNAME is acquired.

$TIMEOUT is in seconds and defaults to 60. (NB: 0 means not to wait for
the lock at all.)

This suits workflows that need to alter the account without deleting it.

=cut

sub create_shared ( $username, $timeout = undef ) {
    return _create( $username, $timeout, 'lock_shared_p' );
}

=head2 promise() = create_exclusive( $USERNAME [, $TIMEOUT ] )

Like C<create_shared()> but creates an exclusive lock.

This is I<probably> only useful for changing account existence state:
create, rename, delete.

=cut

sub create_exclusive ( $username, $timeout = undef ) {
    return _create( $username, $timeout, 'lock_exclusive_p' );
}

sub _create ( $username, $timeout, $funcname ) {
    my $path = _get_path($username);

    return Cpanel::Async::FlockFile->can($funcname)->(
        $path,
        timeout => $timeout // _DEFAULT_TIMEOUT,
    )->catch(
        sub ($err) {
            local $@;
            if ( eval { $err->isa('Cpanel::Exception::IO::FileOpenError') } ) {
                if ( 0 + $err->get('error') == Errno::ENOENT ) {
                    $err = Cpanel::Exception::create(
                        'UserNotFound',
                        [ name => $username ],
                    );
                }
            }

            return Promise::XS::rejected($err);
        }
    );
}

sub _get_path ($username) {
    return "$Cpanel::Config::userdata::Constants::USERDATA_DIR/$username/.existslock";
}

1;
