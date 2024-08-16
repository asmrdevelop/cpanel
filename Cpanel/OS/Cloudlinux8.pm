package Cpanel::OS::Cloudlinux8;

# cpanel - Cpanel/OS/Cloudlinux8.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::OS::Cloudlinux;
use parent 'Cpanel::OS::Rhel8';

use constant is_supported => 1;    # Cloudlinux 8

use constant is_cloudlinux => 1;

use constant pretty_distro => Cpanel::OS::Cloudlinux->pretty_distro;

use constant ea4_install_from_profile_enforce_packages => 0;

use constant ea4_install_repo_from_package => 1;
use constant ea4_from_pkg_url              => 'https://repo.cloudlinux.com/cloudlinux/EA4/cloudlinux-ea4-release-latest-8.noarch.rpm';
use constant ea4_from_pkg_reponame         => 'cloudlinux-ea4-release';
use constant ea4_install_bare_repo         => 0;
use constant ea4_from_bare_repo_url        => undef;
use constant ea4_from_bare_repo_path       => undef;

use constant ea4tooling           => Cpanel::OS::Cloudlinux->ea4_dnf_tooling;
use constant package_repositories => [qw/cloudlinux-PowerTools epel/];

use constant supports_kernelcare_free       => Cpanel::OS::Cloudlinux->supports_kernelcare_free;
use constant has_cloudlinux_enhanced_quotas => 1;
use constant can_become_cloudlinux          => 0;
use constant supports_imunify_360           => 1;

1;

__END__

=encoding utf-8

=head1 NAME

Cpanel::OS::Cloudlinux8 - Cloudlinux 8 custom values

=head1 SYNOPSIS

    # you should not use this package directly
    #   prefer using the abstraction from Cpanel::OS

    use Cpanel::OS ();

=head1 DESCRIPTION

This package represents the supported C<Cloudlinux8> distribution.

You should not use it directly. L<Cpanel::OS> provides an interface
to load and use this package if your distribution is C<Cloudlinux8>.
