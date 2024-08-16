package Cpanel::OS::Cloudlinux9;

# cpanel - Cpanel/OS/Cloudlinux9.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::OS::Cloudlinux;
use parent 'Cpanel::OS::Rhel9';

use constant is_supported => 1;    # Cloudlinux 9

use constant is_cloudlinux => 1;

use constant pretty_distro => Cpanel::OS::Cloudlinux->pretty_distro;

use constant ea4_install_repo_from_package => 1;
use constant ea4_from_pkg_url              => 'https://repo.cloudlinux.com/cloudlinux/EA4/cloudlinux-ea4-release-latest-9.noarch.rpm';
use constant ea4_from_pkg_reponame         => 'cloudlinux-ea4-release';

use constant ea4tooling => Cpanel::OS::Cloudlinux->ea4_dnf_tooling;

use constant supports_kernelcare_free       => Cpanel::OS::Cloudlinux->supports_kernelcare_free;
use constant has_cloudlinux_enhanced_quotas => 1;
use constant can_become_cloudlinux          => 0;
use constant supports_imunify_360           => 1;

use constant who_wins_if_soft_gt_hard => 'hard';

1;

__END__

=encoding utf-8

=head1 NAME

Cpanel::OS::Cloudlinux9 - Cloudlinux 9 custom values

=head1 SYNOPSIS

    # you should not use this package directly
    #   prefer using the abstraction from Cpanel::OS

    use Cpanel::OS ();

=head1 DESCRIPTION

This package represents the supported C<Cloudlinux9> distribution.

You should not use it directly. L<Cpanel::OS> provides an interface
to load and use this package if your distribution is C<Cloudlinux9>.
