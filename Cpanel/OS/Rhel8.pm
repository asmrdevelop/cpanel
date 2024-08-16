package Cpanel::OS::Rhel8;

# cpanel - Cpanel/OS/Rhel8.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use parent 'Cpanel::OS::Rhel';

use constant is_supported => 0;    # Rhel 8 is NOT supported but we use it as a base class for all Rhel derivatives.

use constant binary_sync_source => 'linux-c8-x86_64';

use constant package_release_distro_tag => '~el8';

use constant system_package_providing_perl => 'perl-interpreter';

use constant ea4_install_from_profile_enforce_packages => 1;

1;

__END__

=encoding utf-8

=head1 NAME

Cpanel::OS::Rhel8 - Rhel 8 custom values

=head1 SYNOPSIS

    # you should not use this package directly
    #   prefer using the abstraction from Cpanel::OS

    use Cpanel::OS ();

=head1 DESCRIPTION

This package represents the supported C<Rhel8> distribution.

You should not use it directly. L<Cpanel::OS> provides an interface
to load and use this package if your distribution is C<Rhel8>.
