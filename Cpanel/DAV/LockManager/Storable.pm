package Cpanel::DAV::LockManager::Storable;

# cpanel - Cpanel/DAV/LockManager/Storable.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use IO::Handle;
use Cpanel::SafeFile     ();
use Cpanel::SafeStorable ();

use strict;

#
# This reference implementation of the lock management database interface
# provides an example of the simplest case of a pluggable lock management
# backend mechanism which can be swapped in for any other sort of
# implementation without concern for the operation of the lock manager
# itself.
#

#
# Create a new lock manager context.  Optionally accepts an array
# containing a default set of locks.
#
sub new {
    my $class = shift;

    my $obj = {
        'filename' => shift,
        'lock'     => undef,
        'fh'       => undef,
    };

    return bless $obj, $class;
}

sub close {
    my ($self) = @_;

    $self->_close();
    return;
}

sub _load {
    my ($self) = @_;

    $self->{'fh'} ||= IO::Handle->new();

    # There is a race condition that we could use the clobbering form
    # if it was created just after we check.
    if ( -f $self->{'filename'} ) {
        $self->{'lock'} = Cpanel::SafeFile::safeopen( $self->{'fh'}, '+<', $self->{'filename'} );
        return unless $self->{'lock'};

        $self->{'lock_db'} = eval { Cpanel::SafeStorable::fd_retrieve( $self->{'fh'} ); };
        if ( ref $self->{'lock_db'} ne 'ARRAY' ) {
            print STDERR "Lock database Storable file does not contain a lock database. Repairing...\n";
            $self->{'lock_db'} = [];
            unless ( $self->_write() ) {
                print STDERR "Cannot recreate lock database Storable file.\n";
                return;
            }
        }
        $self->{'lock_db'} = [ map { bless $_, "Cpanel::DAV::Lock" } @{ $self->{'lock_db'} } ];
    }
    else {
        $self->{'lock'} = Cpanel::SafeFile::safeopen( $self->{'fh'}, '+>', $self->{'filename'} );
        return unless $self->{'lock'};

        $self->{'lock_db'} = [];
        Storable::nstore_fd( $self->{'lock_db'}, $self->{'fh'} );
    }
    return 1;
}

sub _write {
    my ($self) = @_;
    seek( $self->{'fh'}, 0, 0 );
    eval {
        Storable::nstore_fd( $self->{'lock_db'} || [], $self->{'fh'} );
        1;
    } or do {

        # TODO : Need better logging.
        print STDERR "Failed to flush the LockManager::Storable object.\n";
        return;
    };
    return 1;
}

sub _save {
    my ($self) = @_;

    if ( $self->{'lock'} ) {

        # save the data
        $self->_write() or return;
        Cpanel::SafeFile::safeclose( $self->{'fh'}, $self->{'lock'} );
    }
    $self->{'fh'}   = undef;
    $self->{'lock'} = undef;

    return 1;
}

sub _close {
    my ($self) = @_;

    Cpanel::SafeFile::safeclose( $self->{'fh'}, $self->{'lock'} ) if $self->{'lock'};
    $self->{'fh'}   = undef;
    $self->{'lock'} = undef;
}

#
# Given a normalized string representation of a resource path, return
# the first lock found.  Otherwise, return undef if none is located.
#
sub get {
    my ( $self, $path, $use_cache ) = @_;

    unless ($use_cache) {    # if the lock_db is already loaded we don't need to load it twice
        unless ( $self->_load() ) {
            die "Unable to obtain file lock.\n";
        }
        $self->_close();
    }

    foreach my $lock ( @{ $self->{'lock_db'} } ) {
        if ( $lock->path eq $path ) {
            return $lock;
        }
    }

    return;
}

#
# Given a path string, return all objects indexed whose path is a descendant
# of the one specified.
#
sub list_descendants {
    my ( $self, $path ) = @_;

    unless ( $self->_load() ) {
        die "Unable to obtain file lock.\n";
    }

    $self->_close();
    return grep { $_->path ne '/' } @{ $self->{'lock_db'} } if $path eq '/';
    return grep { index( $_->path, "$path/" ) == 0 } @{ $self->{'lock_db'} };
}

#
# Given a Cpanel::DAV::Lock object, replace any other locks whose
# path corresponds to that which is stored in the list.
#
sub update {
    my ( $self, $lock ) = @_;

    unless ( $self->_load() ) {
        die "Unable to obtain file lock.\n";
    }

    for ( my $i = 0; $self->{'lock_db'}->[$i]; $i++ ) {
        if ( $self->{'lock_db'}->[$i]->path eq $lock->path ) {
            $self->{'lock_db'}->[$i] = $lock;
        }
    }
    $self->_save();

    return $lock;
}

#
# Add the given lock object to the list.
#
sub add {
    my ( $self, $lock ) = @_;

    unless ( $self->_load() ) {
        die "Unable to obtain file lock.\n";
    }
    push @{ $self->{'lock_db'} }, $lock;
    $self->_save();

    return $lock;
}

#
# Given a lock, the database record which contains the corresponding
# path will be removed.
#
sub remove {
    my ( $self, $lock ) = @_;

    unless ( $self->_load() ) {
        die "Unable to obtain file lock.\n";
    }
    for ( my $i = 0; $self->{'lock_db'}->[$i]; $i++ ) {
        if ( $self->{'lock_db'}->[$i]->path eq $lock->path ) {
            splice @{ $self->{'lock_db'} }, $i, 1;
        }
    }
    $self->_save();
}

1;

__END__
Copyright (c) 2010, cPanel, Inc. All rights reserved.
This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See L<perlartistic>.
