package Cpanel::Exception::JSONParseError;

# cpanel - Cpanel/Exception/JSONParseError.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Exception::Caller );

use Cpanel::LocaleString ();

#metadata parameters:
#   error
#   path    - optional
#
sub _default_phrase {
    my ($self) = @_;

    if ( $self->get('path') && $self->get('dataref') ) {
        if ( defined ${ $self->get('dataref') } ) {
            return Cpanel::LocaleString->new(
                'The system failed to parse the [asis,JSON] stream data “[_1]” from the file “[_2]” because of an error: [_3]',
                substr( ${ $self->get('dataref') }, 0, 1024 ),
                $self->get('path'),
                $self->get('error'),
            );
        }
        else {
            return Cpanel::LocaleString->new(
                'The system tried to parse a [asis,JSON] buffer from the file “[_1]”, but the [asis,JSON] parser received no data.',
                $self->get('path'),
            );
        }
    }
    elsif ( $self->get('path') ) {
        return Cpanel::LocaleString->new(
            'The system failed to parse the [asis,JSON] stream from the file “[_1]” because of an error: [_2]',
            $self->get('path'),
            $self->get('error'),
        );
    }

    my $caller_name = $self->_get_caller_name();
    if ( $caller_name && $self->get('dataref') ) {
        if ( defined ${ $self->get('dataref') } ) {
            return Cpanel::LocaleString->new(
                'The system failed to parse the [asis,JSON] stream data “[_1]” for the caller “[_2]” because of an error: [_3]',
                substr( ${ $self->get('dataref') }, 0, 1024 ),
                $caller_name,
                $self->get('error')
            );
        }
        else {
            return Cpanel::LocaleString->new(
                'The system tried to parse a [asis,JSON] buffer from the caller “[_1]”, but the [asis,JSON] parser received no data.',
                $caller_name,
            );
        }
    }
    elsif ($caller_name) {
        return Cpanel::LocaleString->new(
            'The system failed to parse the [asis,JSON] stream for the caller “[_1]” because of an error: [_2]',
            $caller_name,
            $self->get('error')
        );

    }

    return Cpanel::LocaleString->new(
        'The system failed to parse the [asis,JSON] stream: [_1]',
        $self->get('error'),
    );
}

1;
