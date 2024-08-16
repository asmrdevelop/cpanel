package Whostmgr::API::1::IPv6;

# cpanel - Whostmgr/API/1/IPv6.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::APICommon::Persona ();

use constant NEEDS_ROLE => {
    ipv6_disable_account => 'WebServer',
    ipv6_enable_account  => 'WebServer',
    ipv6_range_add       => 'WebServer',
    ipv6_range_edit      => 'WebServer',
    ipv6_range_list      => 'WebServer',
    ipv6_range_remove    => 'WebServer',
    ipv6_range_usage     => 'WebServer',
};

#
# Enable IPv6 for an account
#
sub ipv6_enable_account {
    my ( $args, $metadata, $api_info_hr ) = @_;

    my $user  = $args->{'user'};
    my $range = $args->{'range'};

    if ( !$user ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = "Missing parameter:  user";
        return;
    }

    if ( !$range ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = "Missing parameter:  range";
        return;
    }

    my $err_obj = _get_child_account_error( $metadata, $api_info_hr, $user );
    return if $err_obj;

    require Cpanel::IPv6::ApiSupport;
    my ( $ret, $msg ) = Cpanel::IPv6::ApiSupport::enable_ipv6_for_user( $user, $range );

    if ($ret) {
        $metadata->{'result'} = 1;
        $metadata->{'reason'} = 'OK';
        return $msg;    # On success, this will be a hash with the new address info
    }
    else {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $msg;
        return;
    }
}

#
# Disable IPv6 for an account
#
sub ipv6_disable_account {
    my ( $args, $metadata, $api_info_hr ) = @_;

    my $user = $args->{'user'};

    if ( !$user ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = "Missing parameter:  user";
        return;
    }

    my $err_obj = _get_child_account_error( $metadata, $api_info_hr, $user );
    return if $err_obj;

    require Cpanel::IPv6::ApiSupport;
    my ( $ret, $msg ) = Cpanel::IPv6::ApiSupport::disable_ipv6_for_user($user);

    if ($ret) {
        $metadata->{'result'} = 1;
        $metadata->{'reason'} = 'OK';
    }
    else {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $msg;
    }

    return;
}

sub _get_child_account_error ( $metadata, $api_info_hr, $users ) {
    my $err_obj;

    $api_info_hr = {} if ( !defined $api_info_hr || ref $api_info_hr ne 'HASH' );

    $users =~ s/\s+//g;
    my @user_list = split( /\,/, $users );

    foreach my $username (@user_list) {

        ( my $str, $err_obj ) = Cpanel::APICommon::Persona::get_whm_expect_parent_error_pieces( $api_info_hr->{'persona'}, $username );

        if ($str) {
            $metadata->set_not_ok($str);
        }

        return $err_obj if $err_obj;
    }

    return;
}

#
# Add a new ipv6 range
#
sub ipv6_range_add {
    my ( $args, $metadata ) = @_;

    my $name = $args->{'name'};

    if ( !$name ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = "Missing parameter:  name";
        return;
    }

    my $range = $args->{'range'};

    if ( !$range ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = "Missing parameter:  range";
        return;
    }

    require Cpanel::IPv6::ApiSupport;
    my ( $ret, $msg ) = Cpanel::IPv6::ApiSupport::ipv6_range_add($args);

    if ($ret) {
        $metadata->{'result'} = 1;
        $metadata->{'reason'} = 'OK';
    }
    else {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $msg;
    }

    return;
}

#
# Add a new ipv6 range
#
sub ipv6_range_edit {
    my ( $args, $metadata ) = @_;

    my $name = $args->{'name'};

    if ( !$name ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = "Missing parameter:  name";
        return;
    }

    require Cpanel::IPv6::ApiSupport;
    my ( $ret, $msg ) = Cpanel::IPv6::ApiSupport::ipv6_range_edit($args);

    if ($ret) {
        $metadata->{'result'} = 1;
        $metadata->{'reason'} = 'OK';
    }
    else {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $msg;
    }

    return;
}

#
# Remove an ipv6 range
#
sub ipv6_range_remove {
    my ( $args, $metadata ) = @_;

    my $name = $args->{'name'};

    if ( !$name ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = "Missing parameter:  name";
        return;
    }

    require Cpanel::IPv6::ApiSupport;
    my ( $ret, $msg ) = Cpanel::IPv6::ApiSupport::ipv6_range_remove($name);

    if ($ret) {
        $metadata->{'result'} = 1;
        $metadata->{'reason'} = 'OK';
    }
    else {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $msg;
    }

    return;
}

#
# Get a list of all the ipv6 ranges and their attributes
#
sub ipv6_range_list {
    my ( $args, $metadata ) = @_;

    require Cpanel::IPv6::ApiSupport;
    my ( $ret, $msg ) = Cpanel::IPv6::ApiSupport::ipv6_range_list();

    if ($ret) {
        $metadata->{'result'} = 1;
        $metadata->{'reason'} = 'OK';
        return { 'range' => $msg };
    }
    else {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $msg;
    }

    return;
}

#
# Get the usage for an ipv6 range
#
sub ipv6_range_usage {
    my ( $args, $metadata ) = @_;

    my $name = $args->{'name'};

    if ( !$name ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = "Missing parameter:  name";
        return;
    }

    require Cpanel::IPv6::ApiSupport;
    my ( $ret, $msg ) = Cpanel::IPv6::ApiSupport::ipv6_range_usage($name);

    if ($ret) {
        $metadata->{'result'} = 1;
        $metadata->{'reason'} = 'OK';
        return { 'usage' => $msg };
    }
    else {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $msg;
    }

    return;
}

1;
