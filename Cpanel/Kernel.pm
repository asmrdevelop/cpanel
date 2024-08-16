package Cpanel::Kernel;

# cpanel - Cpanel/Kernel.pm                        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::OSSys::Env                ();
use Cpanel::Sys::Uname                ();
use Cpanel::Version::Compare::Package ();

=head1 FUNCTIONS

=head2 C<< can_modify_kernel() >>

Returns whether the current environment supports modifying the kernel.

Some systems, like LXC or Virtuozzo, do not allow the kernel to be modified;
these are typically container environments.  In these cases, the kernel is
usually provided by a host environment, so the host environment must be
modified.

B<Returns:> 1 if the kernel can be modified; 0 otherwise.

=cut

sub can_modify_kernel {
    my $envtype = Cpanel::OSSys::Env::get_envtype();
    return 0 if $envtype eq 'lxc' || $envtype eq 'virtuozzo' || $envtype eq 'xen enterprise pv' || $envtype eq 'xen pv' || $envtype eq 'vzcontainer';
    return 1;
}

=head2 C<< get_running_version() >>

Returns the currently running kernel version, as reported by C<uname>.

=cut

sub get_running_version {
    return ( Cpanel::Sys::Uname::syscall_uname() )[2];
}

#Accepts a version string, such as that from uname.
#
#Returns:
#   2 if kernel > given version
#   1 if kernel == given version
#   0 otherwise
#
sub system_is_at_least {
    my ($standard) = @_;

    return Cpanel::Version::Compare::Package::version_cmp( get_running_version(), $standard ) + 1;
}

1;
