package Cpanel::DB::Map::User;

# cpanel - Cpanel/DB/Map/User.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

## no critic qw(TestingAndDebugging::RequireUseWarnings)
use Cpanel::DB::Map::DB ();

use parent qw( Cpanel::DB::Map::Named );

sub new {
    my ( $class, $args ) = @_;
    my $self = $class->init($args);
    return bless $self, $class;
}

sub init {
    my ( $class, $args ) = @_;
    $args->{'dbs'} = ref $args->{'dbs'} && @{ $args->{'dbs'} } ? $args->{'dbs'} : [];

    return {
        'name'   => $args->{'name'},
        'dbs'    => $args->{'dbs'},
        'server' => $args->{'server'} || '',
    };
}

sub _find_db {
    my ( $self, $name ) = @_;

    die "Name of DB cannot be empty!" if !length $name;

    # call the element directly instead of the method as it is much faster
    my ($user) = grep { $_->{'name'} eq $name } @{ $self->{'dbs'} };

    return $user;
}

sub db {
    my ( $self, $name ) = @_;
    my $db = $self->_find_db($name);

    return $db if $db;
    return;
}

sub dbs {
    return grep { defined $_ && $_ =~ tr/ \t\r\n\f//c } @{ $_[0]->{'dbs'} };
}

sub server {
    my ( $self, $new_server ) = @_;

    if ($new_server) {
        $self->{'server'} = $new_server;
    }
    return $self->{'server'};
}

#Argument can either be a DB name or a Cpanel::DB::Map::DB instance.
sub add_db {
    my ( $self, $name ) = @_;

    require Cpanel::Validate::DB::Name;
    if ( Cpanel::Validate::DB::Name::reserved_database_check($name) ) {
        return;
    }
    if ( UNIVERSAL::isa( $name, 'Cpanel::DB::Map::DB' ) ) {
        if ( !$self->_find_db( $name->name ) ) {
            $name->add_user( { 'user_object' => $self } );
            push @{ $self->{'dbs'} }, $name;
        }
    }
    else {
        if ( !length $name ) {
            require Cpanel::Carp;
            die "Cannot add an empty DB name!" . Cpanel::Carp::safe_longmess();
        }

        my $db = $self->_find_db($name);
        if ( !$db ) {
            $db = Cpanel::DB::Map::DB->new( { 'name' => $name } );
            $db->add_user( { 'user_object' => $self } );
            push @{ $self->{'dbs'} }, $db;
        }
    }
    return;
}

sub remove_db {
    my ( $self, $name ) = @_;

    require Cpanel::Validate::DB::Name;
    if ( Cpanel::Validate::DB::Name::reserved_database_check($name) ) {
        return;
    }

    if ( !length $name ) {
        require Cpanel::Carp;
        die "Cannot remove a DB with an empty name!" . Cpanel::Carp::safe_longmess();
    }

    foreach my $db ( $self->dbs() ) {
        $db->remove_user( $self->name() );
    }

    my @new_list = grep { $_->name() ne $name } $self->dbs();
    return $self->{'dbs'} = \@new_list;
}

1;

=pod

=head1 NAME

Cpanel::DB::User

=head1 METHODS

=over

=item add_db($db)

Add db to the list of databases that the user has privileges to

=item remove_db($db)

Remove db to the list of databases that the user has privileges to

=item dbs()

Return the list of database objects that the user has privileges to

=item db($db)

Return the database object for the given database name

=back

=cut
