package Cpanel::Exception::cPStoreError;

# cpanel - Cpanel/Exception/cPStoreError.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# This exception class represents errors from the cPanel Store.
#
# This is an application-level exception; hence, it does NOT include
# network transmission information.
#----------------------------------------------------------------------

use strict;
use warnings;

use parent qw( Cpanel::Exception );

use Cpanel::LocaleString ();

#Three arguments required:
#
#   - request
#   - type (cP API calls this “error” as of January 2016)
#   - message
#
# Optional arguments:
#   - cache_time (epoch, use when rethrowing a cached exception)
#
#Note that “request” can be any string that helps the error-consuming human
#figure out what failed. Network details (e.g., REST/HTTP) are irrelevant.
#
sub _default_phrase {
    my ($self) = @_;

    if ( length $self->get('cache_time') ) {
        return Cpanel::LocaleString->new(
            'The [asis,cPanel Store] previously returned an error ([_1]) on [datetime,_2,datetime_format_long] in response to the request “[_3]”: [_4]',
            ( map { $self->get($_) } qw( type cache_time request message ) ),
        );
    }

    if ( length $self->get('message') ) {
        return Cpanel::LocaleString->new(
            'The [asis,cPanel Store] returned an error ([_1]) in response to the request “[_2]”: [_3]',
            ( map { $self->get($_) } qw( type request message ) ),
        );
    }

    return Cpanel::LocaleString->new(
        'The [asis,cPanel Store] returned an error ([_1]) in response to the request “[_2]”.',
        ( map { $self->get($_) } qw( type request ) ),
    );
}

1;
