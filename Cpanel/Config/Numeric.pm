package Cpanel::Config::Numeric;

# cpanel - Cpanel/Config/Numeric.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::Config::LoadConfig ();

sub load_numeric_Config {
    my ($file) = @_;
    my $ref = Cpanel::Config::LoadConfig::loadConfig( $file, undef, '=' );
    delete @{$ref}{ grep { $ref->{$_} !~ m{^[0-9]+$} } keys %{$ref} };    # remove non-numeric values
    return $ref;
}

1;
