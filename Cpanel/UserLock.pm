package Cpanel::UserLock;

# cpanel - Cpanel/UserLock.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::UserLock

=head1 SYNOPSIS

    if (my $lock = Cpanel::UserLock::create_shared_if_exists('hank')) {
        # During this block 'hank' will always exist; anything
        # that tries to delete that account via cPanel code should
        # block.

    }
    else {
        # If we got here then the account doesn’t exist.
    }

    {
        my $lock = Cpanel::UserLock::create_shared_or_die('hank');

        # 'hank' will always exist in this block; if it didn’t exist
        # then an exception was just thrown.
    }

=head1 DESCRIPTION

This module provides a convenient tool for checking existence of a user
and guaranteeing that user’s continued existence while the caller interacts
with it.

=head1 THE PROBLEM THAT THIS MODULE SOLVES

Historically much cPanel & WHM code looks like this:

    if (my $cpuser_obj = _load_cpuser_file($username)) {
        _do_thing_with_user($username);
    }
    else {
        print "User $username doesn’t exist.\n";
    }

There is a race condition here, though: even though the load of $cpuser_obj
confirms the account’s existence, that confirmation only applies for the
moment when the cpuser file is loaded. In the code above, by the time we call
C<_do_thing_with_user($username)> the account could be deleted.

What we need to solve this is a lock on the user’s existence, such that
while the lock is held nothing can alter the user. That’s what this module
provides.

=head1 SEE ALSO

L<Cpanel::Async::UserLock> provides the underlying implementation.

=cut

#----------------------------------------------------------------------

use Carp ();

use Cpanel::PromiseUtils    ();
use Cpanel::Async::UserLock ();

use constant _DEFAULT_SHARED_TIMEOUT => 60;

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $user_lock_or_undef = create_shared_if_exists( $USERNAME [, $TIMEOUT] )

The optional $TIMEOUT is in seconds. It defaults to 60.

Returns either:

=over

=item * undef, if the user doesn’t exist.

=item * The resolved value of the promise that
L<Cpanel::Async::UserLock>’s function of the same name returns.

(You I<probably> should just treat this object as having no interface other
than its destructor.)

=back

If anything else happens then an exception is thrown. That could include,
e.g., some failure to ascertain the user’s existence.

B<NOTE:> Timeouts are also considered failures because this interface exists
not merely to confirm account existence but also to B<enforce> it; that
enforcement requires a lock.

=cut

sub create_shared_if_exists ( $username, $timeout = undef ) {
    my $result = _get_result( $username, $timeout );

    if ( my $err = $result->error() ) {
        local $@;
        if ( eval { $err->isa('Cpanel::Exception::UserNotFound') } ) {
            return undef;
        }

        Carp::croak $err;
    }

    return $result->get();
}

#----------------------------------------------------------------------

=head2 $user_lock = create_shared_or_die( $USERNAME [, $TIMEOUT] )

Like C<create_shared_if_exists()> but will throw rather than returning
undef if the user doesn’t exist.

=cut

sub create_shared_or_die ( $username, $timeout = undef ) {
    return _get_result( $username, $timeout )->get();
}

sub _get_result ( $username, $timeout ) {
    $timeout //= _DEFAULT_SHARED_TIMEOUT;

    return Cpanel::PromiseUtils::wait_anyevent(
        Cpanel::Async::UserLock::create_shared( $username, $timeout ),
    );
}

1;
