
# cpanel - Whostmgr/TicketSupport/DataStore.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Whostmgr::TicketSupport::DataStore;

use strict;

use Carp                    ();
use Cpanel::CachedDataStore ();

=head1 NAME

Whostmgr::TicketSupport::DataStore

=head1 DESCRIPTION

Manipulate /var/cpanel/supportauth.store

=cut

sub datastore_file { return '/var/cpanel/supportauth.store'; }

=head1 METHODS

=head2 Whostmgr::TicketSupport::DataStore->new()

Open the datastore for reading and/or updating.

Unlike the usual Cpanel::CachedDataStore usage, the lock is held for as long as the object
persists, even if a save has occurred, so if you want to release the lock, you need to either
explicitly destroy the object or let it fall out of scope.

=cut

sub new {
    my ( $package, %args ) = @_;

    # initialize the datastore #
    my $cds = Cpanel::CachedDataStore::loaddatastore( datastore_file(), 1, undef, { 'mode' => 0600 } );
    die q{Failed to load the datastore file "/var/cpanel/supportauth.store": $!}
      if !$cds;

    my $self = {
        %args,
        'cds'    => $cds,
        '_dirty' => 0
    };

    return bless $self, $package;
}

=head2 $store->get()

Get either a single key or the entire datastore contents.

  my $entire_contents = $store->get();
  my $foo = $entire_contents->{'foo'};

    or

  my $foo = $store->get('foo');

=cut

sub get {
    my ( $self, $name ) = @_;
    Carp::croak '[STATE] datastore has already had cleanup or abort called!'
      if !defined $self->{'cds'};
    return $self->{'cds'}{'data'}{$name} if defined $name;
    return $self->{'cds'}{'data'};
}

=head2 $store->set()

  Set either a single key or the entire datastore contents.

  $store->set(key, value); # set a single entry
  $store->set(hashref);    # replace the entire contents with this data structure

  For convenience, store() returns $self so you can chain a call to save().

=cut

sub set {
    my ( $self, $item, $value ) = @_;
    Carp::croak '[STATE] datastore has already had cleanup or abort called!'
      if !defined $self->{'cds'};
    if ( ref $item eq 'HASH' ) {
        $self->{'cds'}{'data'} = $item;
    }
    else {
        $self->{'cds'}{'data'}{$item} = $value;
    }
    $self->{'_dirty'} = 1;
    return $self;
}

=head2 $store->cleanup()

Save, if changes were made, and then release the lock on the file.

=cut

sub cleanup {
    my ($self) = @_;

    Carp::croak '[STATE] datastore has already had cleanup or abort called!'
      if !defined $self->{'cds'};

    # if dirty save, otherwise abort; either way release the lock #
    if ( $self->{'_dirty'} ) {
        die 'failed to save the datastore to "' . datastore_file() . qq{": $!}
          if !Cpanel::CachedDataStore::savedatastore( datastore_file(), $self->{'cds'} );
        $self->{'_dirty'} = 0;
    }
    else {
        $self->{'cds'}->abort();
    }

    # burn the datastore reference, we no longer have the lock so the state is no longer guaranteed #
    delete $self->{'cds'};

    return $self;
}

=head2 $store->abort()

Abort changes, if any, and then release the lock on the file.

=cut

sub abort {
    my ($self) = @_;

    Carp::croak '[STATE] datastore has already had cleanup or abort called!'
      if !defined $self->{'cds'};

    # if dirty save, otherwise abort; either way release the lock #
    $self->{'cds'}->abort();
    $self->{'_dirty'} = 0;

    # burn the datastore reference, we no longer have the lock so the state is no longer guaranteed #
    delete $self->{'cds'};

    return $self;
}

1
