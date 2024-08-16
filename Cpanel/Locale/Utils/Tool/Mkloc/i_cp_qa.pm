package Cpanel::Locale::Utils::Tool::Mkloc::i_cp_qa;

# cpanel - Cpanel/Locale/Utils/Tool/Mkloc/i_cp_qa.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

sub create_target_phrase {
    my ( $ns, $key, $phrase ) = @_;

    my $bn_safe_key = $key;

    if ( $bn_safe_key =~ tr{~][}{} ) {

        # will be a function via item #1 in rt 78989
        $bn_safe_key =~ s{~}{_TILDE_}g;
        $bn_safe_key =~ s{\[}{~[}g;
        $bn_safe_key =~ s{\]}{~]}g;
    }

    # PBI 5074: allow for DOM check:
    # $phrase .= " [output,strong,(maketexted),class,maketexted,rel,$bn_safe_key]"; ## no extract maketext
    $phrase .= " (maketexted: $bn_safe_key)";    ## no extract maketext

    return $phrase;
}

sub get_i_tag_config_hr {
    return {
        display_name    => 'cPanel QA locale',
        fallback_locale => 'en',
    };
}

1;
