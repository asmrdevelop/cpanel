package Cpanel::DB::Map::Owner;

# cpanel - Cpanel/DB/Map/Owner.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::DB::Map::DB   ();
use Cpanel::Debug         ();
use Cpanel::DB::Map::User ();

use parent qw( Cpanel::DB::Map::User Cpanel::DB::Map::Admin );    # perlpkg is really fragile in including base classes

sub init {
    my ( $class, $args ) = @_;
    my $self = $class->SUPER::init($args);

    $self->{'cpuser'}   = $args->{'cpuser'};
    $self->{'db'}       = $args->{'db'} || 'UNKNOWN';
    $self->{'users'}    = [];
    $self->{'noprefix'} = {};

    return $self;
}

sub _find_user {
    my ( $self, $name ) = @_;

    if ( !length $name ) {
        require Cpanel::Carp;
        die Cpanel::Carp::safe_longmess("Name of DB user cannot be empty!");
    }

    my ($user) = grep { $_->name() eq $name } @{ $self->{'users'} };
    return $user;
}

sub add_dbuser {
    my ( $self, $args ) = @_;

    my $name   = $args->{'dbuser'};
    my $server = $args->{'server'};

    #This should not happen in production but showed up in development,
    #so there may be some buggy implementation somewhere.
    #
    #This needs protection because the DB map is used for authorizing access
    #to functions like rename and set_password.
    #
    if ( $name eq $self->name() ) {
        require Cpanel::Carp;
        die Cpanel::Carp::safe_longmess("A DB map Owner cannot own itself!");
    }

    if ( defined $name && !$self->_find_user($name) ) {
        my $user = Cpanel::DB::Map::User->new( { 'name' => $name, 'server' => $server } );
        push @{ $self->{'users'} }, $user;
    }

    return;
}

# This will auto-create the DB in the map, but not the DB user.
sub add_db_for_dbuser {
    my ( $self, $db, $name ) = @_;

    my $user = $self->_find_user($name);

    if ( !$user && $name ne $self->name() ) {

        # Only warn if the name is not the db owner (cpuser minus any dot, or underscore that may exist when prefixing is disabled)
        warn "No user in $self->{'db'} DB map named “$name”!";
    }
    my $db_obj = $self->_find_db($db);

    require Cpanel::Validate::DB::Name;

    if ( Cpanel::Validate::DB::Name::reserved_database_check($db) ) {
        warn "add_db_for_dbuser($db, $name): “$db” is a reserved DB name.";
        return;
    }

    if ( $user && !ref $db_obj ) {
        $db_obj = Cpanel::DB::Map::DB->new( { 'name' => $db } );
        $self->add_db($db_obj);
    }

    if ( $db_obj && $user ) {
        $user->add_db($db_obj);
    }

    return;
}

sub remove_db_for_dbuser {
    my ( $self, $db, $name ) = @_;

    require Cpanel::Validate::DB::Name;
    if ( Cpanel::Validate::DB::Name::reserved_database_check($db) ) {
        return;
    }

    my $user = $self->_find_user($name);

    if ($user) {
        $user->remove_db($db);
    }

    return;
}

sub dbusers {
    my ($self) = @_;
    return grep { defined $_ && !/^\s*$/ } @{ $self->{'users'} };
}

sub dbuser {
    my ( $self, $name ) = @_;
    my $user = $self->_find_user($name);

    return $user if $user;
    return 0;
}

sub remove_db {
    my ( $self, $name ) = @_;

    die "Name of DB cannot be empty!" if !length $name;

    $self->SUPER::remove_db($name);

    foreach my $dbuser ( @{ $self->{'users'} } ) {
        $dbuser->remove_db($name);
    }

    return;
}

sub remove_dbuser {
    my ( $self, $name ) = @_;
    my @new_list = grep { $_->name() ne $name } $self->dbusers();
    $self->{'users'} = \@new_list;

    Cpanel::Debug::log_info( "$self->{'db'}: Remove dbuser $name for owner " . $self->name() . " on $self->{'server'}" );

    return;
}

sub no_prefix {
    my ( $self, $name ) = @_;

    if ($name) {
        $self->{'noprefix'}{$name} = 1;
    }
    return keys %{ $self->{'noprefix'} };
}

1;

=pod

=head1 NAME

Cpanel::DB::Owner

=head1 DESCRIPTION

This object represents the collection of dbuser and databases
the owner has.

=head1 SYNOPSIS

Cpanel::DB::Owner should never be instantiate outside of Cpanel::DB::Map

=head1 INHERITANCE

Cpanel::DB::Owner isa Cpanel::DB::User

=head1 METHOD

=over

=item add_dbuser($user)

Add $user to the list of database users for the owner

=item add_db_for_dbuser($db, $dbuser)

Assign $db to $dbuser

=item dbusers

Return a list of all dbusers objects

=item dbuser($user)

Return the user object for $name

=item remove_dbuser($user)

Remove $user from the list of users for the owner

=item remove_db($db)

remove $db from the list of dbs for the owner

=item remove_db_for_dbuser($db, $dbuser)

Unassign $db to $dbuser

=back

=cut
