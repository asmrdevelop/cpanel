package Cpanel::DB::Map::DB;

# cpanel - Cpanel/DB/Map/DB.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::DB::Map::User ();

use parent qw(Cpanel::DB::Map::Named);

sub new {
    my ( $class, $args ) = @_;
    my $self = $class->init($args);

    return bless $self, $class;
}

sub init {
    my ( $class, $args ) = @_;
    $args->{'users'} = ref $args->{'users'} && @{ $args->{'users'} } ? $args->{'users'} : [];

    return {
        'name'   => $args->{'name'},
        'users'  => $args->{'users'},
        'server' => $args->{'server'},
    };
}

sub _find_user {
    my ( $self, $name ) = @_;

    my ($user) = grep { $_->name() eq $name } @{ $self->{'users'} };

    return $user;
}

sub users {
    my ($self) = @_;
    return @{ $self->{'users'} };
}

sub add_user {
    my ( $self, $args ) = @_;
    my $name     = $args->{'name'};
    my $server   = $args->{'server'};
    my $user_obj = $args->{'user_object'};
    if ($user_obj) {
        push @{ $self->{'users'} }, $user_obj;
    }
    elsif ( !$self->_find_user($name) ) {
        my $user = Cpanel::DB::Map::User->new( { 'name' => $name, 'server' => $server } );
        push @{ $self->{'users'} }, $user;
    }
}

sub remove_user {
    my ( $self, $name ) = @_;

    my @new_list = grep { $_->name() ne $name } $self->users();
    $self->{'users'} = \@new_list;
}

sub server {
    my ( $self, $new_server ) = @_;

    if ($new_server) {
        $self->{'server'} = $new_server;
    }
    return $self->{'server'};
}

1;

=pod

=head1 METHODS

=over

=item add_user($user)

Add user from the list of users that have access to the database

=item remove_user($user)

Remove user from the list of users that have access to the database

=item users()

Return list of user objects that have access to the database

=back

=cut
