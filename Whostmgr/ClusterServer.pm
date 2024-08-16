#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - Whostmgr/ClusterServer.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Whostmgr::ClusterServer;

use strict;

use Cpanel::CachedDataStore        ();
use Cpanel::SafeFile               ();
use Cpanel::SafeDir::MK            ();
use Cpanel::Validate::Username     ();
use Cpanel::Validate::Domain::Tiny ();
use Cpanel::Validate::IP           ();
use Whostmgr::ClusterServer::Utils ();

our $SERVERS_DB_FILE = q{/var/cpanel/clusterserver/servers.db};

sub new {
    my ( $class, %opts ) = @_;

    return if $>;    # only root can create some objects

    my $self = bless { %opts, pid => $$, data => {} }, $class;
    return $self;
}

# acquire lock + read file
sub load {
    my ($self) = @_;
    _verify_called_as_object_method($self);

    return if $self->{lock};    # file already read

    $self->_create_directory();
    $self->{lock} = Cpanel::SafeFile::safelock($SERVERS_DB_FILE);

    Cpanel::CachedDataStore::loaddatastore( $SERVERS_DB_FILE, 0, $self->{data}, { donotlock => 1, enable_memory_cache => 0 } );

    return 1;
}

sub reload {
    my ($self) = @_;
    _verify_called_as_object_method($self);

    $self->abort();
    return $self->load();
}

sub get_list {
    my ($self) = @_;
    _verify_called_as_object_method($self);
    $self->load();

    my $copy = {};
    foreach my $h ( keys %{ $self->{data} } ) {
        $copy->{$h} = { %{ $self->{data}->{$h} } };
    }

    return $copy;    # returns a copy not a reference
}

sub count {
    my ($self) = @_;
    _verify_called_as_object_method($self);
    $self->load();

    return scalar keys %{ $self->{data} };
}

sub get_list_scramble_keys {
    my ($self) = @_;
    _verify_called_as_object_method($self);

    my $list = $self->get_list();    # this is a copy

    foreach my $host ( keys %$list ) {

        $list->{$host}->{signature} = Whostmgr::ClusterServer::Utils::get_key_signature( $list->{$host}->{key} );
        delete $list->{$host}->{key};
    }

    return $list;
}

# add a new value if not already defined
sub add {
    my ( $self, %opts ) = @_;
    _verify_called_as_object_method($self);

    return unless Cpanel::Validate::Username::is_valid( $opts{user} );
    my $user = $opts{user};

    return unless Cpanel::Validate::Domain::Tiny::validdomainname( $opts{name}, 1 ) || Cpanel::Validate::IP::is_valid_ip( $opts{name} );
    my $name = $opts{name};

    return unless $name && $opts{key} && $opts{user};

    $self->load();

    my $list = $self->{data};
    return if exists $list->{$name};

    my $clean_key = Whostmgr::ClusterServer::Utils::sanitize_key( $opts{key} );
    return unless $clean_key && $user;
    $list->{$name}->{key}  = $clean_key;
    $list->{$name}->{user} = $user;

    return Whostmgr::ClusterServer::Utils::get_key_signature($clean_key);
}

sub update {
    my ( $self, $name, $opts ) = @_;

    return unless $opts && ref $opts eq 'HASH' && scalar keys %$opts;

    _verify_called_as_object_method($self);
    return unless Cpanel::Validate::Domain::Tiny::validdomainname( $name, 1 ) || Cpanel::Validate::IP::is_valid_ip($name);

    $self->load();

    my $list = $self->{data};

    return unless $name && exists $list->{$name};
    my $server = $list->{$name};

    # currently update key and/or user
    my $ok;
    if ( $opts->{key} ) {
        my $clean_key = Whostmgr::ClusterServer::Utils::sanitize_key( $opts->{key} );
        return unless $clean_key;
        $server->{key} = $clean_key;
        $ok = 1;
    }
    if ( $opts->{user} ) {
        return unless Cpanel::Validate::Username::is_valid( $opts->{user} );
        $server->{user} = $opts->{user};
        $ok = 1;
    }

    return unless $ok;    # nothing to update

    return { user => $server->{user}, signature => Whostmgr::ClusterServer::Utils::get_key_signature( $server->{key} ) };
}

# delete a value
sub delete {
    my ( $self, $name ) = @_;
    _verify_called_as_object_method($self);
    return unless Cpanel::Validate::Domain::Tiny::validdomainname( $name, 1 ) || Cpanel::Validate::IP::is_valid_ip($name);
    $self->load();

    my $list = $self->{data};
    return unless $name && exists $list->{$name};

    delete $list->{$name};
    return 1;
}

sub save {
    my ($self) = @_;
    _verify_called_as_object_method($self);

    # never save if nothing has been loaded
    return unless $self->{lock};

    if ( $self->{data} && keys %{ $self->{data} } ) {
        $self->_create_directory();
        Cpanel::CachedDataStore::store_ref( $SERVERS_DB_FILE, $self->{data}, { mode => 0600 } );
    }
    else {
        unlink($SERVERS_DB_FILE);
    }

    $self->_release_lock();

    return 1;
}

sub abort {
    my ($self) = @_;
    _verify_called_as_object_method($self);
    $self->_release_lock();

    return;
}

sub _create_directory {
    my ($self) = @_;

    my $dir = $SERVERS_DB_FILE;
    $dir =~ s{/[^/]+$}{};
    Cpanel::SafeDir::MK::safemkdir( $dir, 0700 );    # create dir if missing and adjust permissions
    return;
}

sub _release_lock {
    my ($self) = @_;
    _verify_called_as_object_method($self);

    return unless $self->{'pid'} == $$;

    Cpanel::SafeFile::safeunlock( $self->{lock} ) if $self->{lock};
    $self->{lock} = undef;

    return;
}

sub _verify_called_as_object_method {
    my $pkg = shift;
    ref($pkg) eq __PACKAGE__ or die '' . ( caller(0) )[3] . " was not called as an object method\n";
    return;
}

sub DESTROY {
    my ($self) = @_;

    # call abort
    return unless $self;
    $self->_release_lock();
    return;
}

1;
