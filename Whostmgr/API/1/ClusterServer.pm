
# cpanel - Whostmgr/API/1/ClusterServer.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Whostmgr::API::1::ClusterServer;

use strict;
use warnings;

use Whostmgr::ClusterServer ();
use Whostmgr::ACLS          ();

use constant NEEDS_ROLE => {
    add_configclusterserver    => undef,
    delete_configclusterserver => undef,
    update_configclusterserver => undef,
    list_configclusterservers  => undef,
    has_trust                  => undef,
};

my $locale;

sub add_configclusterserver {
    my ( $args, $metadata ) = @_;

    $metadata->{name}     = $args->{name} if defined $args->{name};
    $metadata->{user}     = $args->{user} if defined $args->{user};
    $metadata->{'result'} = 0;    # flag as an error

    return unless _check_args( $args, $metadata, [ 'name', 'key', 'user' ] );

    my $ls = Whostmgr::ClusterServer->new();
    my $signature;
    if ( !$ls || !( $signature = $ls->add( name => $args->{name}, key => $args->{key}, user => $args->{user} ) ) ) {
        $metadata->{'reason'} = $locale->maketext( "The system was unable to add server “[_1]” to the configuration cluster servers list.", $args->{name} );
        return;
    }
    if ( !$ls->save() ) {
        $metadata->{'reason'} = $locale->maketext("The system was unable to save the configuration cluster servers list.");
        return;
    }

    _metadata_ok($metadata);
    $metadata->{signature} = $signature;

    return;
}

sub delete_configclusterserver {
    my ( $args, $metadata ) = @_;

    $metadata->{name}     = $args->{name} if defined $args->{name};
    $metadata->{'result'} = 0;                                        # flag as an error

    return unless _check_args( $args, $metadata, ['name'] );

    my $ls = Whostmgr::ClusterServer->new();
    if ( !$ls || !$ls->delete( $args->{name} ) ) {
        $metadata->{'reason'} = $locale->maketext( "The system was unable to delete server “[_1]” from the configuration clusters list.", $args->{name} );
        return;
    }
    if ( !$ls->save() ) {
        $metadata->{'reason'} = $locale->maketext("The system was unable to save the configuration cluster servers list.");
        return;
    }

    _metadata_ok($metadata);

    return;
}

sub update_configclusterserver {
    my ( $args, $metadata ) = @_;

    $metadata->{'result'} = 0;
    $metadata->{'name'}   = $args->{name} if defined $args->{name};

    return unless _check_args( $args, $metadata, ['name'] ) &&    # can update only one of them
      ( _check_args( $args, $metadata, ['user'] ) || _check_args( $args, $metadata, ['key'] ) );

    my $ls = Whostmgr::ClusterServer->new();
    my $server;
    if ( !$ls || !( $server = $ls->update( $args->{name}, $args ) ) ) {
        $metadata->{'reason'} = $locale->maketext( "Cannot update server “[_1]”.", $args->{name} );
        return;
    }
    if ( !$ls->save() ) {
        $metadata->{'reason'} = $locale->maketext("The system was unable to save the configuration cluster servers list.");
        return;
    }

    _metadata_ok($metadata);
    for my $field (qw/user signature/) {
        $metadata->{$field} = $server->{$field};
    }

    return;
}

# never return a clear version of the remote access key via the api
sub list_configclusterservers {
    my ( $args, $metadata ) = @_;

    return unless _init_and_check_acls($metadata);

    my $ls = Whostmgr::ClusterServer->new();
    my $list;
    if ( !$ls || !( $list = $ls->get_list_scramble_keys() ) ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $locale->maketext("Cannot get configuration cluster servers list.");
        return;
    }

    _metadata_ok($metadata);

    return $list;
}

sub has_trust {
    my ( $args, $metadata ) = @_;
    require Cpanel::Locale;
    $locale ||= Cpanel::Locale->get_handle();

    if ( !defined $args->{'host'} ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $locale->maketext( "Missing argument: [_1]", 'host' );
        return;
    }

    if ( !Whostmgr::ACLS::checkacl('clustering') ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $locale->maketext("You must have the clustering ACL to complete this request.");
        return;
    }

    require Cpanel::DNSLib::PeerStatus;
    _metadata_ok($metadata);
    return { has_trust => Cpanel::DNSLib::PeerStatus::has_reverse_trust( $args->{host}, $args->{althost} ) ? 1 : 0 };
}

# helpers
sub _metadata_ok {
    my $metadata = shift or return;

    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';

    return;
}

sub _init_and_check_acls {
    my $metadata = shift || {};

    # initialize locale
    require Cpanel::Locale;
    $locale ||= Cpanel::Locale->get_handle();

    # check acls
    if ( !Whostmgr::ACLS::hasroot() ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $locale->maketext("You do not have permission to read and edit configuration cluster servers.");
        return;
    }

    return 1;
}

sub _check_args {
    my ( $args, $metadata, $expect ) = @_;

    # should be first
    return unless _init_and_check_acls($metadata);

    return unless $expect && ref $expect eq 'ARRAY';

    foreach my $k (@$expect) {
        next if defined $args->{$k};
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $locale->maketext( "Missing argument: [_1]", $k );
        return;
    }

    # all arguments ar defined as expected
    return 1;
}

1;
