package Whostmgr::API::1::ACLS;

# cpanel - Whostmgr/API/1/ACLS.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Whostmgr::ACLS ();

use constant NEEDS_ROLE => {
    myprivs     => undef,
    listacls    => undef,
    saveacllist => undef,
};

sub myprivs {
    my ( undef, $metadata ) = @_;
    $metadata->@{qw(result reason)} = ( 1, 'OK' );

    my %dynamic_acls =
      map { $_->{acl} => $_->{default_value} }
      map { @{$_} } values( ( Whostmgr::ACLS::get_dynamic_acl_lists() )[0]->%* );

    return { privileges => [ { %dynamic_acls, %Whostmgr::ACLS::ACL } ] };
}

sub listacls {
    my ( undef, $metadata ) = @_;
    my $aclref = Whostmgr::ACLS::list_acls();
    my @acls_list;
    while ( my ( $name, $privileges ) = each %$aclref ) {
        push @acls_list, { 'name' => $name, 'privileges' => $privileges };
    }
    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';
    return { 'acl' => \@acls_list };
}

sub saveacllist {
    my ( $args, $metadata ) = @_;
    my ( $result, $reason ) = Whostmgr::ACLS::save_acl_list(%$args);
    $metadata->{'result'} = $result ? 1 : 0;
    $metadata->{'reason'} = $reason;
    return;
}

1;
