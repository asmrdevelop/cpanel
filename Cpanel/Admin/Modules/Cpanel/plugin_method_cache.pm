#                                      Copyright 2024 WebPros International, LLC
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited.

package Cpanel::Admin::Modules::Cpanel::plugin_method_cache;

use cPstrict;

use parent qw( Cpanel::Admin::Base );

use Cpanel::JSON ();

use constant cache_file => '/var/cpanel/plugins/common/methodcache.json';

=encoding utf-8

=head1 NAME

Cpanel::Admin::Modules::Cpanel::plugin_method_cache

=head1 SYNOPSIS

  use Cpanel::AdminBin::Call ();

  Cpanel::AdminBin::Call::call( "Cpanel", "plugin_method_cache", $action, {} );

=cut

sub _actions {
    return qw(GET_CACHE SAVE_CACHE);
}

use constant _allowed_parents => (
    __PACKAGE__->SUPER::_allowed_parents(),
);

sub GET_CACHE {
    _ensure_cache();
    my $cache_data = eval { Cpanel::JSON::LoadFile(cache_file) };
    return $cache_data;
}

sub SAVE_CACHE ( $self, $data ) {
    _ensure_cache();
    Cpanel::JSON::DumpFile( cache_file, $data );
    return 1;
}

sub _ensure_cache {
    if ( !-e cache_file ) {
        Cpanel::JSON::DumpFile( cache_file, {} );
        chmod( 0600, cache_file );
    }
    return 1;
}

1;
