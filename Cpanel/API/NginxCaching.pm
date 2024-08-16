package Cpanel::API::NginxCaching;

# cpanel - Cpanel/API/NginxCaching.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf8

=head1 NAME

Cpanel::API::NginxCaching

=head1 DESCRIPTION

This module contains UAPI methods related to the ea-nginx package installed as a caching reverse proxy

=head1 FUNCTIONS

=cut

use cPstrict;

use Cpanel                 ();
use Cpanel::Exception      ();
use Cpanel::AdminBin::Call ();

my $allow_demo = { allow_demo => 1 };

our %API = (
    clear_cache        => $allow_demo,
    reset_cache_config => $allow_demo,
    enable_cache       => $allow_demo,
    disable_cache      => $allow_demo,
);

=head2 clear_cache()

This function clears the user's cache

=cut

sub clear_cache ( $args, $result ) {

    _can_we_use_this_feature(0);
    my ( $results, $warnings_ref ) = Cpanel::AdminBin::Call::call( 'Cpanel', 'nginx', 'CLEAR_CACHE' );
    $result->error($@) if $@;

    return 1 unless $result->errors();
    return 0;
}

=head2 reset_cache_config ()

Forces ea-nginx to rebuild the user's cache config

=cut

sub reset_cache_config ( $args, $result ) {

    _can_we_use_this_feature(1);
    my ( $results, $warnings_ref ) = Cpanel::AdminBin::Call::call( 'Cpanel', 'nginx', 'RESET_CACHE_CONFIG' );
    $result->error($@) if $@;

    return 1 unless $result->errors();
    return 0;
}

=head2 enable_cache ()

Enable the user's cache.

=cut

sub enable_cache ( $args, $result ) {

    _can_we_use_this_feature(1);
    my ( $results, $warnings_ref ) = Cpanel::AdminBin::Call::call( 'Cpanel', 'nginx', 'ENABLE_CACHE' );
    $result->error($@) if $@;

    return 1 unless $result->errors();
    return 0;
}

=head2 disable_cache ()

Disable the user's cache.

=cut

sub disable_cache ( $args, $result ) {

    _can_we_use_this_feature(1);
    my ( $results, $warnings_ref ) = Cpanel::AdminBin::Call::call( 'Cpanel', 'nginx', 'DISABLE_CACHE' );
    $result->error($@) if $@;

    return 1 unless $result->errors();
    return 0;
}

###############################################
#
# Helpers
#
###############################################

our $_nginx_installed_file = '/usr/local/cpanel/scripts/ea-nginx';

sub _can_we_use_this_feature ($needs_feature) {

    # first, ea-nginx needs to have been installed
    # further it cannot be in standalone mode
    # and some of this requires a feature being set

    #TODO: should these be cached_values?
    if ( !-e $_nginx_installed_file ) {
        die Cpanel::Exception::create( 'FeatureNotEnabled', '“[_1]” is not installed on the system.', ['ea-nginx'] );
    }

    if ( $needs_feature && !Cpanel::hasfeature('toggle_nginx_caching') ) {
        die Cpanel::Exception::create( 'FeatureNotEnabled', '“[_1]” is not installed on the system.', ['toggle_nginx_caching'] );
    }

    return;
}

