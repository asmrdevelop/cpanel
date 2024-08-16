package Cpanel::OS::Rhel9;

# cpanel - Cpanel/OS/Rhel9.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use parent 'Cpanel::OS::Rhel8';

use Cpanel::OS ();

use constant is_supported => 0;    # Rhel 9 is NOT supported but we use it as a base class for all Rhel derivatives.

use constant networking => 'NetworkManager';

use constant package_repositories => [qw/epel crb/];

use constant binary_sync_source => 'linux-c9-x86_64';

use constant package_release_distro_tag => '~el9';

use constant program_to_apply_kernel_args => 'grubby';

use constant mysql_versions_use_repo_template => [qw/8.0/];

use constant mariadb_minimum_supported_version => '10.5';

# Work around a bug in RHEL 9's rsync not fixed until 9.2:
sub rsync_old_args { return Cpanel::OS::minor() < 2 ? ['--old-args'] : [] }    ## no critic qw(CpanelOS) -- behavior is conditional on minor release

# The default crypto policy on RHEL9 does not include SHA1, we need to add it for some packages which still require it
use constant crypto_policy_needs_sha1 => 1;

# not all packages listed from the default profile are available
use constant ea4_install_from_profile_enforce_packages => 0;

# Rhel 9 uses a different RPM.
use constant jetbackup_repo_pkg => 'https://repo.jetlicense.com/centOS/jetapps-repo-4096-latest.rpm';

# See Cpanel::DNSLib::find_zonedir and the RHEL9 bind specfile
use constant var_named_permissions => {
    'mode'      => 0770,
    'ownership' => [ 'root', 'named' ],
};

sub packages_supplemental ($self) {
    my @packages = $self->SUPER::packages_supplemental()->@*;

    # ...
    @packages = sort grep {
        my $p = $_;

        !( grep { $p =~ $_ } (qr{^python2}) )
    } @packages;

    push @packages, qw{ glibc-langpack-en s-nail };

    return \@packages;
}

sub packages_required ($self) {
    my @packages = $self->SUPER::packages_required()->@*;

    @packages = sort grep {
        my $p = $_;
        !( grep { $p eq $_ } qw{ dnf-plugin-universal-hooks python36 python3-docs mailx } )
          && !( grep { $p =~ $_ } (qr{^python2}) )
    } @packages;

    push @packages, qw{ python3 libnsl2 dbus-tools openldap-compat };

    return \@packages;
}

1;

__END__

=encoding utf-8

=head1 NAME

Cpanel::OS::Rhel9 - Rhel 9 custom values

=head1 SYNOPSIS

    # you should not use this package directly
    #   prefer using the abstraction from Cpanel::OS

    use Cpanel::OS ();

=head1 DESCRIPTION

This package represents the supported C<Rhel8> distribution.

You should not use it directly. L<Cpanel::OS> provides an interface
to load and use this package if your distribution is C<Rhel8>.
