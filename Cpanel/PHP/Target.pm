
# cpanel - Cpanel/PHP/Target.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::PHP::Target;

use strict;
use warnings;

=head1 MODULE

=head2 NAME

Cpanel::PHP::Target

=head2 DESCRIPTION

Check the status of the current php RPM target

=head2 is_target_enabled

Check if any 'cpanel-phpXX' RPM target is enabled.

Return false when the target is anything other than 'installed'
return true in all other cases

=cut

sub is_target_enabled {
    return get_enabled_target() ? 1 : 0;
}

=head2 get_enabled_target

Check if any 'cpanel-phpXX' RPM target is enabled and return the version if so.

Return undef when the target is anything other than 'installed' or 'unmanaged'
return the version without periods in all other cases

=cut

sub get_enabled_target {
    my $rpm_prefix = 'cpanel-php';

    # Require these to avoid "circular dependencies" that lead to redefinition
    # warnings.
    require Cpanel::Binaries;
    my $ver = Cpanel::Binaries::PHP_MAJOR();

    # Also, don't load these without eval, as sometimes this codepath
    # gets invoked by *system perl*, which won't have IO::SigGuard due to the
    # dep chain here requiring it in Cpanel::FileUtils::Lines
    local $@;
    my $target_settings = '';
    eval {
        require Cpanel::RPM::Versions::File;
        my $enabler = Cpanel::RPM::Versions::File->new();
        $target_settings = $enabler->target_settings( $rpm_prefix . $ver ) // '';

        # Look if they have the "legacy" target enabled when no target for PHP_MAJOR
        if ( !$target_settings ) {
            $ver             = Cpanel::Binaries::PHP_MAJOR_LEGACY();
            $target_settings = $enabler->target_settings( $rpm_prefix . $ver ) // '';
        }
    };
    return ( $@ || grep { $target_settings eq $_ } qw{installed unmanaged} ) ? $ver : undef;
}

1;
