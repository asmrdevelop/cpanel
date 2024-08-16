package Cpanel::HTTP::QueryString::Legacy;

# cpanel - Cpanel/HTTP/QueryString/Legacy.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#
# DO NOT USE Cpanel/HTTP/QueryString/Legacy.pm
# in new code
#

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings)

use Cpanel::Encoder::URI ();
use Cpanel::IxHash       ();

#This "legacy" form parsing will parse this:
#
# foo=bar&foo=baz&foo=qux
#
# .. into this:
#
# { foo => bar, foo-0 => baz, foo-1 => qux }
#
#NOTE: This expects a string reference ONLY.
#
sub legacy_parse_query_string_sr {
    my ($stringref) = @_;

    my ( %form, %counter, $name, $value );

    # Note: we only use this to preserve order, however it has
    # the side effect of HTML encoding everything which is probably
    # not what we want.
    tie( %form, 'Cpanel::IxHash' ) if $$stringref =~ tr{&}{};    # No need to preserve order if only one item

    for my $pair ( split m{&}, $$stringref ) {
        ( $name, $value ) = split( /=/, $pair, 2 );              #we can't encode here as it will encode '/'s

        for ( $name, $value ) {
            next unless defined;
            next if !tr<%+><>;
            $_ = Cpanel::Encoder::URI::uri_decode_str($_);
        }

        # %form stores copies of the same name
        # by incrementing as -1, -2 etc
        # {
        #   'name' => 'value'
        #   'name-0' => 'value',
        #   'name-1' => 'value'
        # }
        #
        #NB: always increment, but test on the pre-increment value
        if ( $counter{$name}++ ) {
            $form{ "$name-" . ( $counter{$name} - 2 ) } = $value;
        }
        else {
            $form{$name} = $value;
        }
    }

    return \%form;
}

1;
