
# cpanel - Cpanel/InterfaceLock.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::InterfaceLock;

use strict;

use Errno                       qw[ENOENT EEXIST];
use Cpanel::Fcntl::Constants    ();
use File::Path                  ();
use Cpanel::InterfaceLock::Tiny ();
use Cpanel::Locale::Lazy 'lh';

=head1 NAME

Cpanel::InterfaceLock

=head1 DESCRIPTION

This module contains a set of calls used to lock out access to a named feature.
To use it, you need to add lock checks to your interfaces that need to be disabled
when the lock is held.  Then when you are ready to lock out the sub-system, you call the
lock() method. When you are ready for the sub-system to be available again, you unlock().
You can check if the lock is active with the object using the is_locked() method or if
you just know the name or name and path of the lock, use the lock_exists module
method.

=head1 ASSUMPTIONS

1. There is only one process that will be trying to call the lock() and unlock() method.

2. Most users will be calling the lock_exists method to determine if there is a
    lockout currently active.

=head1 CONSTRUCTION

=head2 new

Creates a named interface lock management object.

Arguments

  - class - string
  - config - hash - containing the following attributes:
    - name - string - name of the lock.

    - unlock_on_destroy - boolean - optional, if not set the lock will be removed when the
    instance is destroyed. Otherwise, if its truthy, the lock will be removed on destruction and
    if its falsy, it will not be destroyed on destruction.

    - base_path - string - Optional, root path where the lock file is stored. To create or remove a lock,
    the current user must have read/write/execute permission on this directory. Callers of the lock_exists()
    method only need read permission.

    - user - string - Optional, if provided will be used to make this a per-user lock rather than a global lock.

=cut

sub new {
    my ( $class, %config ) = @_;

    if ( !$config{name} ) {
        die lh()->maketext('You did not provide the lock name.');
    }

    $config{unlock_on_destroy} = 1 if !defined $config{unlock_on_destroy};
    $config{pid}               = $$;

    # Determine the lock base path
    if ( defined $config{base_path} ) {
        $config{base_path} = Cpanel::InterfaceLock::Tiny::make_lock_path( $config{base_path} );
    }
    else {
        $config{base_path} = Cpanel::InterfaceLock::Tiny::make_lock_path();
    }

    # Build any prerequisites
    if ( !-e $config{base_path} ) {
        File::Path::make_path( $config{base_path}, { mode => 0711 } )
          or die lh()->maketext( 'The system could not create the base path “[_1]” for the “[_2]” lock: [_3]', $config{base_path}, $config{name}, $! );
    }

    $config{path} = $config{base_path} . $config{name};

    if ( defined $config{user} ) {
        $config{path} .= ':' . $config{user};
    }
    return bless \%config, $class;
}

=head1 MEMBER METHODS

=head2 lock

Acquires the lock based on the configured properties.

Returns

   0  if the lock could not be acquired.
  -1 if exists already. Its up to the caller to decide if this is a failure.
   1  if the lock was acquired.

=cut

sub lock {
    my ($self) = @_;
    my $fh;

    my $ret = sysopen(
        $fh,
        $self->{path},
        $Cpanel::Fcntl::Constants::O_CREAT | $Cpanel::Fcntl::Constants::O_EXCL | $Cpanel::Fcntl::Constants::O_WRONLY
    );
    my $error = $!;
    if ( !$ret ) {
        if ( $! == EEXIST ) {
            return -1;
        }
        else {
            warn lh()->maketext( 'The system cannot create the lock with the “[_1]” path: [_2]', $self->{path}, $error );
            return 0;
        }
    }
    print $fh "1";
    close($fh);
    return 1;
}

=head2 unlock

Releases the lock based on the configured properties.

Arguments

  - name - String -

Returns

  0 if the lock can not be unlocked for some reason.


=cut

sub unlock {
    my ($self) = @_;
    my $ret    = unlink $self->{path};
    my $error  = $!;
    if ( !$ret ) {
        if ( $! == ENOENT ) {
            return 1;    #Already unlocked
        }
        warn lh()->maketext( 'The system cannot release the lock at the “[_1]” path: [_2]', $self->{path}, $error );
        return 0;        #Can't unlock for some reason
    }
    return 1;
}

=head2 is_locked

Checks if the lock is in place with the configured properties.

=cut

sub is_locked {
    my ($self) = @_;
    return -e $self->{path} ? 1 : 0;
}

=head2 DESTROY

Cleans up the object during destruction if it's still around.

=cut

sub DESTROY {
    my ($self) = @_;
    if ( $self->{pid} == $$ && $self->{unlock_on_destroy} ) {
        $self->unlock();
    }

    return;
}

1;
