package Cpanel::Locale::Utils::Tool::Mkloc::i_cp_rtl_en;

# cpanel - Cpanel/Locale/Utils/Tool/Mkloc/i_cp_rtl_en.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::CPAN::Locale::Maketext::Utils::Phrase ();

sub create_target_phrase {
    my ( $ns, $key, $phrase ) = @_;

    my $target_phrase = '';
    for my $piece ( reverse @{ Cpanel::CPAN::Locale::Maketext::Utils::Phrase::phrase2struct($phrase) } ) {
        if ( !ref($piece) ) {

            # We could reverse words instead of characters:
            # $target_phrase .= join( ' ', reverse( split /\s+/, $piece ) ); # Reverse words

            # Reverse characters:
            # should be safe since we are operating on byte strings, if not then we want warnings/errors to alert us to the problem
            utf8::decode($piece);
            $piece = join( '', reverse( split '', $piece ) );
            utf8::encode($piece);
            $target_phrase .= $piece;
        }
        else {
            $target_phrase .= $piece->{'orig'};
        }
    }

    return $target_phrase;
}

sub get_i_tag_config_hr {
    return {
        display_name    => 'cPanel Right-to-Left testing locale',
        fallback_locale => 'ar',
    };
}

1;
