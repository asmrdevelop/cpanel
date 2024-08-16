package Cpanel::API::DNSSEC;

# cpanel - Cpanel/API/DNSSEC.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::AdminBin::Call ();

my $demo    = { allow_demo => 1 };
my $no_demo = { allow_demo => 0 };

our %API = (
    _needs_role    => 'DNS',
    _needs_feature => 'dnssec',

    # These calls work for multiple domains
    enable_dnssec    => $no_demo,
    disable_dnssec   => $no_demo,
    fetch_ds_records => $demo,
    disable_dnssec   => $no_demo,
    set_nsec3        => $no_demo,
    unset_nsec3      => $no_demo,

    # These are specific to a domain and key_id
    activate_zone_key   => $no_demo,
    deactivate_zone_key => $no_demo,
    add_zone_key        => $no_demo,
    remove_zone_key     => $no_demo,
    import_zone_key     => $no_demo,
    export_zone_key     => $no_demo,
    export_zone_dnskey  => $no_demo,
);

sub enable_dnssec {
    my ( $args, $result ) = @_;

    my @domains     = $args->get_length_required_multiple('domain');
    my $nsec_config = {
        'use_nsec3'        => $args->get('use_nsec3'),
        'nsec3_opt_out'    => $args->get('nsec3_opt_out'),
        'nsec3_iterations' => $args->get('nsec3_iterations'),
        'nsec3_narrow'     => $args->get('nsec3_narrow'),
        'nsec3_salt'       => $args->get('nsec3_salt'),
    };

    my $algo_config = {
        'algo_num'  => $args->get('algo_num'),
        'key_setup' => $args->get('key_setup'),
        'active'    => $args->get('active'),
    };

    my $enabled = _call_adminbin( 'ENABLE_DNSSEC', [ $nsec_config, $algo_config, \@domains ] );

    $result->data($enabled);

    return 1;
}

sub fetch_ds_records {
    my ( $args, $result ) = @_;

    my @domains    = $args->get_length_required_multiple('domain');
    my $ds_records = _call_adminbin( 'FETCH_DS_RECORDS', [ \@domains ] );

    $result->data($ds_records);

    return 1;
}

sub disable_dnssec {
    my ( $args, $result ) = @_;

    my @domains  = $args->get_length_required_multiple('domain');
    my $disabled = _call_adminbin( 'DISABLE_DNSSEC', [ \@domains ] );

    $result->data($disabled);

    return 1;
}

sub set_nsec3 {
    my ( $args, $result ) = @_;

    my @domains     = $args->get_length_required_multiple('domain');
    my $nsec_config = {
        'nsec3_opt_out'    => $args->get_length_required('nsec3_opt_out'),
        'nsec3_iterations' => $args->get_length_required('nsec3_iterations'),
        'nsec3_narrow'     => $args->get_length_required('nsec3_narrow'),
        'nsec3_salt'       => $args->get_length_required('nsec3_salt'),
    };

    my $set_nsec3 = _call_adminbin( 'SET_NSEC3', [ $nsec_config, \@domains ] );

    $result->data($set_nsec3);

    return 1;
}

sub unset_nsec3 {
    my ( $args, $result ) = @_;

    my @domains     = $args->get_length_required_multiple('domain');
    my $unset_nsec3 = _call_adminbin( 'UNSET_NSEC3', [ \@domains ] );

    $result->data($unset_nsec3);

    return 1;
}

sub activate_zone_key {
    my ( $args, $result ) = @_;

    my $domain = $args->get_length_required('domain');
    my $key_id = $args->get_length_required('key_id');

    my $activate = _call_adminbin( 'ACTIVATE_ZONE_KEY', [ $domain, $key_id ] );

    $result->data($activate);

    return 1;
}

sub deactivate_zone_key {
    my ( $args, $result ) = @_;

    my $domain = $args->get_length_required('domain');
    my $key_id = $args->get_length_required('key_id');

    my $deactivate = _call_adminbin( 'DEACTIVATE_ZONE_KEY', [ $domain, $key_id ] );

    $result->data($deactivate);

    return 1;
}

sub add_zone_key {
    my ( $args, $result ) = @_;

    my $domain     = $args->get_length_required('domain');
    my $key_config = {
        'algo_num' => $args->get_length_required('algo_num'),
        'key_type' => $args->get_length_required('key_type'),
        'key_size' => $args->get('key_size'),
        'active'   => $args->get('active'),
    };

    my $add = _call_adminbin( 'ADD_ZONE_KEY', [ $key_config, $domain ] );

    $result->data($add);

    return 1;
}

sub remove_zone_key {
    my ( $args, $result ) = @_;

    my $domain = $args->get_length_required('domain');
    my $key_id = $args->get_length_required('key_id');

    my $remove = _call_adminbin( 'REMOVE_ZONE_KEY', [ $domain, $key_id ] );

    $result->data($remove);

    return 1;
}

sub import_zone_key {
    my ( $args, $result ) = @_;

    my ( $domain, $key_data, $key_type ) = $args->get_length_required(qw/domain key_data key_type/);

    my $import = _call_adminbin( 'IMPORT_ZONE_KEY', [ $domain, $key_data, $key_type ] );

    $result->data($import);

    return 1;
}

sub export_zone_key {
    my ( $args, $result ) = @_;

    my $domain = $args->get_length_required('domain');
    my $key_id = $args->get_length_required('key_id');

    my $export = _call_adminbin( 'EXPORT_ZONE_KEY', [ $domain, $key_id ] );
    $result->data($export);

    return 1;
}

sub export_zone_dnskey {
    my ( $args, $result ) = @_;

    my $domain = $args->get_length_required('domain');
    my $key_id = $args->get_length_required('key_id');

    my $export = _call_adminbin( 'EXPORT_ZONE_DNSKEY', [ $domain, $key_id ] );
    $result->data($export);

    return 1;
}

sub _call_adminbin {
    my ( $function, $args ) = @_;
    return Cpanel::AdminBin::Call::call( 'Cpanel', 'dnssec', $function, @{$args} );
}

1;
