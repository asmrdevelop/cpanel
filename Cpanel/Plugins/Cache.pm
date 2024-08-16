package Cpanel::Plugins::Cache;

#                                      Copyright 2024 WebPros International, LLC
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited.

use Moo::Role;
use cPstrict;

use Class::Method::Modifiers                            ();
use Cpanel::AdminBin::Call                              ();
use Cpanel::Admin::Modules::Cpanel::plugin_method_cache ();

=head1 MODULE

C<Cpanel::Plugins::Cache>

=head1 DESCRIPTION

C<Cpanel::Plugins::Cache> is a Moo Role that provides a cache for method calls.

=cut

sub setup_cache ( $self, $methods, $time_to_live = 86400 ) {

    my $package = ref $self;

    foreach my $method ( $methods->@* ) {
        Class::Method::Modifiers::install_modifier(
            $package, 'around', $method,
            sub ( $orig, $self ) {
                my $package    = ref $self;
                my $cache_data = _get_cache();

                if ( $cache_data && $cache_data->{$package}{$method} ) {
                    my $cached_time = $cache_data->{$package}{$method}{time} || 0;
                    if ( time - $cached_time < $time_to_live ) {
                        return $cache_data->{$package}{$method}{data};
                    }
                }

                my $result = $orig->($self);

                $cache_data->{$package}{$method}{data} = $result;
                $cache_data->{$package}{$method}{time} = time;
                _save_cache($cache_data);
                return $result;
            }
        );
    }

    return 1;
}

sub _get_cache {
    return Cpanel::AdminBin::Call::call( "Cpanel", "plugin_method_cache", 'GET_CACHE' ) if $>;
    return Cpanel::Admin::Modules::Cpanel::plugin_method_cache::GET_CACHE();
}

sub _save_cache ($data) {
    return Cpanel::AdminBin::Call::call( "Cpanel", "plugin_method_cache", 'SAVE_CACHE', $data ) if $>;
    return Cpanel::Admin::Modules::Cpanel::plugin_method_cache->SAVE_CACHE($data);
}

1;
