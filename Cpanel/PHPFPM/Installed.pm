package Cpanel::PHPFPM::Installed;

# cpanel - Cpanel/PHPFPM/Installed.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=head1 NAME

Cpanel::PHPFPM::Installed

=head1 SYNOPSIS

use Cpanel::PHPFPM::Installed;

my $ret = is_fpm_installed_for_php_version("ea-php99");

my $ret = is_fpm_installed_for_php_version_cached("ea-php99");

=head1 DESCRIPTION

Subroutines to determine if PHP-FPM is installed for a version
of PHP.  Yum is called to find out if the rpm is installed
so this can be expensive and that is why there is a cached
version that will only check a version once.

=head1 SUBROUTINES

=head2 is_fpm_installed_for_php_version

Determine if the PHP-FPM rpm is installed for this version of PHP.

=over 3

=item C<< $package >>

The version of PHP to check for, must be of the form 'ea-phpXX' as in 'ea-php99'.

=back

B<Returns>: Returns a 1 if the rpm is installed or 0 if it is not installed.

=cut

our %php_fpm_installed_for_version;

sub is_fpm_installed_for_php_version {
    my ($package) = @_;

    return 0 if !length $package;

    require Cpanel::PackMan;
    return 1 if Cpanel::PackMan->instance->is_installed("$package-php-fpm");
    return 0;
}

=head2 is_fpm_installed_for_php_version_cached

Determine if the PHP-FPM rpm is installed for this version of PHP.
This version is cached so it will only call yum once for each version
of PHP.

=over 3

=item C<< $package >>

The version of PHP to check for, must be of the form 'ea-phpXX' as in 'ea-php99'.

=back

B<Returns>: Returns a 1 if the rpm is installed or 0 if it is not installed.

=cut

sub is_fpm_installed_for_php_version_cached {
    my ($package) = @_;

    return 0 if !length $package;

    if ( !exists $php_fpm_installed_for_version{$package} ) {
        $php_fpm_installed_for_version{$package} = is_fpm_installed_for_php_version($package);
    }

    return $php_fpm_installed_for_version{$package};
}

1;
