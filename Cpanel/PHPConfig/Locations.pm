package Cpanel::PHPConfig::Locations;

# cpanel - Cpanel/PHPConfig/Locations.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Cpanel::Binaries ();

sub get_system_php_paths {
    _php_paths( 'system', '/usr/local' );
}

sub get_cpphp_php_paths {
    _php_paths( 'cpphp', Cpanel::Binaries::get_prefix("php") );
}

sub _php_paths {
    my $name   = shift;
    my $prefix = shift;
    my $pecl   = $prefix . '/bin/pecl';
    my $pear   = $prefix . '/bin/pear';
    my $phpcli = -x $prefix . '/bin/php-cli' ? $prefix . '/bin/php-cli' : $prefix . '/bin/php';

    return {
        'prefix' => $prefix,
        'php'    => $phpcli,
        'pecl'   => $pecl,
        'pear'   => $pear,
        'name'   => $name,
    };
}

sub get_php_locations {
    my %LOCATIONS = (
        'system' => get_system_php_paths(),
        'cpphp'  => get_cpphp_php_paths(),
    );

    return wantarray ? %LOCATIONS : \%LOCATIONS;
}

1;
