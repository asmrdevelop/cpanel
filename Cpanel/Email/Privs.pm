package Cpanel::Email::Privs;

# cpanel - Cpanel/Email/Privs.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::Transaction::File::JSON ();

use base qw(
  Cpanel::Email::PrivsReader
);

#Overrides PrivsReader's function with this name.
sub _get_transaction {
    my ( $self, $path ) = @_;

    $self->{'_creator_pid'} = $$;

    return Cpanel::Transaction::File::JSON->new(
        path => $path,
    );
}

sub remove_mailman_delegate_from_all_lists {
    my ( $self, $delegate ) = @_;

    die 'The “delegate” parameter is required.' if !length $delegate;

    $self->{'_data'}{'mailman'} ||= {};
    foreach my $list ( keys %{ $self->{'_data'}{'mailman'} } ) {
        if ( $self->{'_data'}{'mailman'}{$list}{'delegates'} ) {
            delete $self->{'_data'}{'mailman'}{$list}{'delegates'}{$delegate};
        }
    }
    return 1;
}

sub remove_mailman_delegates {
    my ( $self, $list, $delegates ) = @_;

    die 'The “list” parameter is required.'      if !length $list;
    die 'The “delegates” parameter is required.' if !$delegates || !ref $delegates;

    return 1 if !$self->{'_data'}{'mailman'}{$list};

    delete @{ $self->{'_data'}{'mailman'}{$list}{'delegates'} }{ @{$delegates} };

    return 1;
}

sub add_mailman_delegates {
    my ( $self, $list, $delegates ) = @_;

    die 'The “list” parameter is required.'      if !length $list;
    die 'The “delegates” parameter is required.' if !$delegates || !ref $delegates;

    @{ $self->{'_data'}{'mailman'}{$list}{'delegates'} }{ @{$delegates} } = (1) x scalar @{$delegates};

    return 1;
}

sub remove_mailman_list {
    my ( $self, $list ) = @_;

    die 'The “list” parameter is required.' if !length $list;

    delete $self->{'_data'}{'mailman'}{$list};

    return 1;
}

sub save {
    my ($self) = @_;

    die "Transaction was already saved!" if $self->{'_transaction_is_done'};

    $self->{'_transaction'}->set_data( $self->{'_data'} );

    my ( $ok, $err ) = $self->{'_transaction'}->save_and_close();
    return ( 0, $err ) if !$ok;

    $self->{'_transaction_is_done'} = 1;

    return 1;
}

sub abort {
    my ($self) = @_;

    my ( $ok, $err ) = $self->{'_transaction'}->abort();
    return ( 0, $err ) if !$ok;

    $self->{'_transaction_is_done'} = 1;

    return 1;
}

sub DESTROY {
    my ($self) = @_;

    #Failed to create the object
    return if !$self->{'_creator_pid'};

    #Already done? Then there's nothing to do.
    return if $self->{'_transaction_is_done'};

    #Forked off the parent? Then let the parent handle it.
    return if $$ != $self->{'_creator_pid'};

    #We probably die()d on instantiation if this happens.
    return if !$self->{'_transaction'};

    my $class = ref $self;
    warn "WARNING: Instance of $class destroyed without save(). Aborting transaction.";

    my ( $ok, $err ) = $self->abort();
    warn $err if !$ok;

    return;
}

1;
