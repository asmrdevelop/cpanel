package Cpanel::Locale::i_cpanel_snowmen;

# cpanel - Cpanel/Locale/i_cpanel_snowmen.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::Locale        ();
use Cpanel::Locale::Utils ();

$Cpanel::Locale::i_cpanel_snowmen::VERSION = '0.7';
@Cpanel::Locale::i_cpanel_snowmen::ISA     = ('Cpanel::Locale');

sub new {
    my $class = shift;

    if ( $> == 0 && !-e "/var/cpanel/i_locales/i_cpanel_snowmen.yaml" ) {
        open my $fh, '>', "/var/cpanel/i_locales/i_cpanel_snowmen.yaml" || die "Could not open “/var/cpanel/i_locales/i_cpanel_snowmen.yaml”: $!";
        print {$fh} "---\n";
        print {$fh} qq{"display_name": '☃ cPanel Snowmen ☃'\n};
        print {$fh} qq{"fallback_locale": 'en'\n};
        close($fh);
    }

    Cpanel::Locale::Utils::init_package();    # Cpanel::Locale::Utils is brought in via Cpanel::Locale

    return $class->SUPER::new();
}
1;
