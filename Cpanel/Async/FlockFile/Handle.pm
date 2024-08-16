package Cpanel::Async::FlockFile::Handle;

# cpanel - Cpanel/Async/FlockFile/Handle.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Async::FlockFile::Handle

=head1 SYNOPSIS

Upgrade to an exclusive lock; use default timeout:

    $handle->relock_exclusive_p();

Downgrade to a shared lock; time out immediately:

    $handle->relock_shared_p(0);

=head1 DESCRIPTION

This object encapsulates the lock created by L<Cpanel::Async::FlockFile>.
It should only be created from that class.

=cut

#----------------------------------------------------------------------

use Cpanel::Async::Flock ();
use Cpanel::Context      ();

#----------------------------------------------------------------------

=head1 METHODS

=head2 $obj = I<CLASS>->new( $LOCKED_FILEHANDLE, $PATH )

Instantiates this class. $LOCKED_FILEHANDLE is a filehandle to the
locked file, and $PATH is its absolute path.

=cut

sub new ( $class, $fh, $path ) {
    return bless [ $fh, $path ], $class;
}

=head2 promise($obj) = I<OBJ>->relock_shared_p( [ $TIMEOUT ] )

Changes I<OBJ>’s lock to a shared lock. $TIMEOUT is the same
as the C<timeout> parameter to L<Cpanel::Async::Flock>.

=cut

sub relock_shared_p ( $self, $timeout = undef ) {
    return $self->_get_relock_p( 'flock_SH', $timeout );
}

=head2 promise($obj) = I<OBJ>->relock_exclusive_p( [ $TIMEOUT ] )

Like C<relock_shared_p()> but changes to an exclusive lock.

=cut

sub relock_exclusive_p ( $self, $timeout = undef ) {
    return $self->_get_relock_p( 'flock_EX', $timeout );
}

#----------------------------------------------------------------------

sub _get_relock_p ( $self, $lock_funcname, $timeout ) {
    Cpanel::Context::must_not_be_void();

    return Cpanel::Async::Flock->can($lock_funcname)->(
        @{$self}[ 0, 1 ], $timeout,
    )->then( sub { $self } );
}

1;
