package Cpanel::Locale::zh_tw;

# cpanel - Cpanel/Locale/zh_tw.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::Locale        ();
use Cpanel::Locale::Utils ();

$Cpanel::Locale::zh_tw::VERSION = '0.7';
@Cpanel::Locale::zh_tw::ISA     = ('Cpanel::Locale');

sub new {
    my $class = shift;

    Cpanel::Locale::Utils::init_package();    # Cpanel::Locale::Utils is brought in via Cpanel::Locale

    return $class->SUPER::new();
}
1;
