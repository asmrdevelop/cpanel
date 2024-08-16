package Cpanel::Validate::AuthProvider;

# cpanel - Cpanel/Validate/AuthProvider.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Validate::FilesystemNodeName ();
use Cpanel::Exception                    ();

sub check_provider_name_or_die {
    my ($provider) = @_;

    # The param is almost always 'provider' not 'provider_name'
    die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'provider' ] ) if !length $provider;

    if ( !Cpanel::Validate::FilesystemNodeName::is_valid($provider) ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The provider name “[_1]” is invalid.', [$provider] );
    }

    require Cpanel::Validate::LineTerminatorFree;
    Cpanel::Validate::LineTerminatorFree::validate_or_die($provider);
    return 1;
}

1;
