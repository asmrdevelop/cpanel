package Cpanel::Exception::Market::Disabled;

# cpanel - Cpanel/Exception/Market/Disabled.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# This exception class represents an indication that the store let us know that
# the Market is disabled by the license provider.
#----------------------------------------------------------------------

use strict;
use warnings;

use parent qw( Cpanel::Exception::Market );

use Cpanel::LocaleString ();
use Cpanel::Market       ();

#Three arguments required:
#
#   - provider (string, e.g., 'cPStore')
#
# Optional arguments:
#   - cache_time (epoch, use when rethrowing a cached exception)
#
sub _default_phrase {
    my ($self) = @_;

    my $disp_name = Cpanel::Market::get_provider_display_name( $self->get('provider') );

    if ( length $self->get('cache_time') ) {
        return Cpanel::LocaleString->new(
            'The license holder disabled the Market as previously indicated by the “[_1]” on [datetime,_2,datetime_format_long].',
            $disp_name,
            $self->get('cache_time'),
        );
    }

    return Cpanel::LocaleString->new(
        '“[_1]” indicated that the Market has been disabled by the license holder.',
        $disp_name,
    );
}

1;
