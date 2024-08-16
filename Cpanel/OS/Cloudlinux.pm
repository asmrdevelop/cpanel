package Cpanel::OS::Cloudlinux;

# cpanel - Cpanel/OS/Cloudlinux.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use parent 'Cpanel::OS::Rhel';

use constant is_supported => 0;    # Base class for CL.

use constant is_cloudlinux => 1;

use constant pretty_distro => 'CloudLinux';

use constant ea4_yum_tooling => [qw{ yum-plugin-universal-hooks ea-cpanel-tools ea-profiles-cloudlinux }];
use constant ea4_dnf_tooling => [qw{ dnf-plugin-universal-hooks ea-cpanel-tools ea-profiles-cloudlinux }];

use constant supports_kernelcare_free => 0;

1;

__END__

=encoding utf-8

=head1 NAME

Cpanel::OS::Cloudlinux - Cloudlinux base class

=head1 SYNOPSIS

    use parent 'Cpanel::OS::Cloudlinux';

=head1 DESCRIPTION

This package is an interface for all Cloudlinux distributions.
You should not use it directly.

=head1 ATTRIBUTES

=head2 supported()

No a supported distribution.

=head2 ea4_yum_tooling()

List of yum_tooling packages.

=head2 ea4_dnf_tooling()

List of dnf_tooling package.

=head2 supports_kernelcare_free()

By default kernelcare_free is not supported.
