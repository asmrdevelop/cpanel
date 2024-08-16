package Whostmgr::API::1::NGINXManager;

# cpanel - Whostmgr/API/1/NGINXManager.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Whostmgr::API::1::Utils               ();
use Cpanel::Exception                     ();
use Cpanel::Transaction::File::JSON       ();
use Cpanel::Transaction::File::JSONReader ();
use Cpanel::Config::userdata              ();
use Cpanel::Validate::Boolean             ();
use Cpanel::AcctUtils::Owner              ();

use Cpanel::Imports;

use File::Glob       ();
use File::Path::Tiny ();

use Types::Serialiser;
use Capture::Tiny;

use constant NEEDS_ROLE => {
    set_cache_config         => undef,
    get_cache_config_system  => undef,
    get_cache_config_users   => undef,
    reset_users_cache_config => undef,
    rebuild_cache_config     => undef,
    clear_cache              => undef,
};

our $ea_nginx_bin = '/usr/local/cpanel/scripts/ea-nginx';
our $valid_users_hr;

# Makes testing easier
our $var_cpanel_userdata = '/var/cpanel/userdata';
our $etc_nginx           = '/etc/nginx/ea-nginx';
our $var_cache_ea_nginx  = '/var/cache/ea-nginx';

=encoding utf-8

=head1 NAME

Whostmgr::API::1::NGINXManager - These functions support the NGINXManager UI.

=head1 SYNOPSIS

    use Whostmgr::API::1::NGINXManager;

    Whostmgr::API::1::NGINXManager::set_config ({ user=>cptest1, enabled=>1 }, {}, {});

=head2 set_config

Sets the enabled flag for the users or system.

B<Args>

    user - An optional list of users to set the enabled flag for.

    enabled - required and must be 1 or 0

B<Output>

    None.

=cut

sub set_cache_config ( $args, $metadata, $api_info_hr ) {
    _require_ea_nginx();

    my @users   = Whostmgr::API::1::Utils::get_length_arguments( $args, 'user' );
    my $enabled = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'enabled' );

    Cpanel::Validate::Boolean::validate_or_die( $enabled, 'enabled' );

    my $ok = 0;
    if (@users) {
        _validate_users(@users);
        foreach my $user (@users) {
            _set_json_enabled( $var_cpanel_userdata . "/$user/nginx-cache.json", $enabled );
            $ok += _run_ea_nginx( $metadata, 'config', $user, '--no-reload' );
        }

        $ok += _run_ea_nginx( $metadata, 'reload' ) if $ok;
    }
    else {
        _set_json_enabled( $etc_nginx . "/cache.json", $enabled );
        $ok += _run_ea_nginx( $metadata, 'reload' );
    }

    if ($ok) {
        Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    }
    else {
        Whostmgr::API::1::Utils::set_metadata_not_ok( $metadata, locale->maketext("Completed with warnings") );
    }

    return;
}

=head2 get_cache_config_system

Gets the config parameters for the system and defaults.

B<Args>

    merge - Optional must be 1, will merge system and
      default values.  Each configuration returned will be the
      fully determined configuration.

    Merge it returns the fully determined configurations, rather than the raw data.

B<Output>

    {
        default => {
            enabled => 1,
        },
        system => {
            enabled => 1,
        },
    }

=cut

sub get_cache_config_system ( $args, $metadata, $api_info_hr ) {
    _require_ea_nginx();

    my $data  = {};
    my $merge = Whostmgr::API::1::Utils::get_length_argument( $args, 'merge' );

    my $system_data = _get_json( $etc_nginx . '/cache.json' );

    my %global_defaults = _ea_nginx_get_global_defaults();

    if ($merge) {
        my %merged = (
            %global_defaults,
            %{$system_data},
        );

        $system_data = \%merged;
    }

    $data->{system}  = $system_data;
    $data->{default} = \%global_defaults;

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return $data;
}

=head2 get_cache_config_users

Gets the config parameters for users

B<Args>

    user - An optional list of users to get the configs for.

    merge - Optional must be 1, will merge the user, system and
      default values.  Each configuration returned will be the
      fully determined configuration.

    NOTE: the output depends on the combination of parameters.

    If users are passed, then it will return only those users.

    If no users are passed, all the users will be returned.

    Merge it returns the fully determined configurations, rather than the raw data.

B<Output>

    {
        users => [
            {
                config => {
                    'enabled' => 1,
                },
                owner  => 'root',
                merged => 0,
                user   => 'cpuser3',
            },
            {
                config => {
                    'enabled' => 1,
                },
                owner  => 'root',
                merged => 0,
                user   => 'cpuser4',
            },
            {
                config => {
                    'enabled' => 1,
                },
                owner  => 'root',
                merged => 0,
                user   => 'cpuser2',
            },
            {
                config => {
                    'enabled' => 1,
                },
                owner  => 'root',
                merged => 0,
                user   => 'cpuser1',
            },
        ]
    }

=cut

sub get_cache_config_users ( $args, $metadata, $api_info_hr ) {
    _require_ea_nginx();
    my $data = [];

    my $merge = Whostmgr::API::1::Utils::get_length_argument( $args, 'merge' );
    my @users = Whostmgr::API::1::Utils::get_length_arguments( $args, 'user' );

    $merge ||= 0;

    if (@users) {
        _validate_users(@users);
    }
    else {
        @users = keys %{ _get_valid_users() } if ( !@users );
    }

    my $system_data     = $merge ? _get_json( $etc_nginx . '/cache.json' ) : undef;
    my %global_defaults = $merge ? _ea_nginx_get_global_defaults()         : ();
    for my $user (@users) {
        my $owner     = Cpanel::AcctUtils::Owner::getowner($user);
        my $user_data = _get_json( $var_cpanel_userdata . "/$user/nginx-cache.json" );

        if ($merge) {
            my %merged = (
                %global_defaults,
                %{$system_data},
                %{$user_data},
            );

            $user_data = \%merged;
        }

        push @{$data}, { user => $user, owner => $owner, config => $user_data, merged => $merge };
    }

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    return { users => $data };
}

=head2 reset_users_cache_config

Removes users configurations resetting them.

B<Args>

    user - An optional list of users to reset the configs for.

    If users are passed, those users are the only ones that are reset.

    If no users are passed, all the users are reset.

B<Output>

    None.

=cut

sub reset_users_cache_config ( $args, $metadata, $api_info_hr ) {
    _require_ea_nginx();

    my @users = Whostmgr::API::1::Utils::get_length_arguments( $args, 'user' );
    _validate_users(@users) if @users;

    if (@users) {
        for my $user (@users) {
            unlink "$var_cpanel_userdata/$user/nginx-cache.json";
        }
    }
    else {
        _delete_glob( $var_cpanel_userdata . "/*/nginx-cache.json" );
    }

    if ( _run_ea_nginx( $metadata, 'config', '--all' ) ) {
        Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    }
    else {
        Whostmgr::API::1::Utils::set_metadata_not_ok( $metadata, locale->maketext("Completed with warnings") );
    }

    return;
}

=head2 rebuild_cache_config

Reset users’ configurations so that they will get the system level values. This removes their configuration completely.

B<Args>

    user - An optional list of users to rebuild the configs for.

    If users are passed, those users are the only ones the configs are rebuilt for.

    If no users are passed, the entire configuration is rebuilt.

B<Output>

    None.

=cut

sub rebuild_cache_config ( $args, $metadata, $api_info_hr ) {
    _require_ea_nginx();

    my $ok    = 0;
    my @users = Whostmgr::API::1::Utils::get_length_arguments( $args, 'user' );
    if (@users) {
        _validate_users(@users);
        foreach my $user (@users) {
            $ok += _run_ea_nginx( $metadata, 'config', $user, '--no-reload' );
        }

        $ok += _run_ea_nginx( $metadata, 'reload' ) if $ok;
    }
    else {
        $ok += _run_ea_nginx( $metadata, 'config', '--all' );
    }

    if ($ok) {
        Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    }
    else {
        Whostmgr::API::1::Utils::set_metadata_not_ok( $metadata, locale->maketext("Completed with warnings") );
    }

    return;
}

=head2 clear_cache

Clear's the cache(s)

B<Args>

    user - An optional list of users to clear the caches for.

    If users are passed, those users are the only ones the caches are cleared for.

    If no users are passed, all the caches are cleared.

B<Output>

    None.

=cut

sub clear_cache ( $args, $metadata, $api_info_hr ) {
    _require_ea_nginx();

    my @users = Whostmgr::API::1::Utils::get_length_arguments( $args, 'user' );

    if (@users) {
        _validate_users(@users);
        foreach my $user (@users) {
            _delete_glob( $var_cache_ea_nginx . "/*/$user/*" );
        }
    }
    else {
        _delete_glob( $var_cache_ea_nginx . "/*/*/*" );
    }

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return;
}

#######################################################
#
# Helpers
#
#######################################################

sub _set_json_enabled ( $fname, $enabled ) {
    my $transaction = Cpanel::Transaction::File::JSON->new( path => $fname, "permissions" => 0644 );
    my $data        = $transaction->get_data();

    $data = {} if ( ref($data) eq "SCALAR" || ref($data) eq "" );

    if ($enabled) {
        $data->{'enabled'} = Types::Serialiser::true;
    }
    else {
        $data->{'enabled'} = Types::Serialiser::false;
    }
    $transaction->set_data($data);

    $transaction->save_pretty_canonical_or_die();
    $transaction->close_or_die();

    return;
}

sub _get_json ($fname) {
    my $data = {};

    my $transaction = Cpanel::Transaction::File::JSONReader->new( path => $fname );
    $data = $transaction->get_data();
    $data = {} if ( !defined $data || $data == \undef );

    return $data;
}

sub _require_ea_nginx () {
    eval { require $ea_nginx_bin; };
    if ($@) {
        die Cpanel::Exception::create( 'EA4PackageIsNotInstalled', [ 'module' => 'ea-nginx' ] );
    }

    return;
}

sub _delete_glob ($glob) {
    for my $item ( File::Glob::csh_glob($glob) ) {

        # File::Path::Tiny::rm does not delete files
        if ( -l $item || -f _ ) {
            unlink($item);
        }
        elsif ( -d $item ) {
            File::Path::Tiny::rm($item);
        }
    }

    return;
}

sub _ea_nginx_get_global_defaults () {
    _require_ea_nginx();

    my %global_defaults = ();

    if ( scripts::ea_nginx->can('caching_defaults') ) {
        %global_defaults = scripts::ea_nginx::caching_defaults();
    }
    else {
        %global_defaults = ( enabled => Types::Serialiser::true );
    }

    return %global_defaults;
}

sub _get_valid_users {
    $valid_users_hr //= { map { $_ eq "nobody" ? () : ( $_ => 1 ) } Cpanel::Config::userdata::load_user_list() };
    return $valid_users_hr;
}

sub _validate_users (@users) {
    my $users_hr = _get_valid_users();
    foreach my $user (@users) {
        if ( !exists $users_hr->{$user} ) {
            die Cpanel::Exception::create( 'InvalidUsername', [ value => $user ] );
        }
    }

    return @users;
}

sub _run_ea_nginx ( $metadata, @args ) {
    my ( $stdout, $stderr, $ok ) = Capture::Tiny::capture {
        eval { scripts::ea_nginx::run(@args) };
        return $@ ? 0 : 1;
    };

    $metadata->add_warning($@) if !$ok;

    return $ok;
}

1;
