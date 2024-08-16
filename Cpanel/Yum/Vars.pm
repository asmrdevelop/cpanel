package Cpanel::Yum::Vars;

# cpanel - Cpanel/Yum/Vars.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::OS               ();
use Cpanel::FileUtils::Write ();

=encoding utf-8

=head1 NAME

Cpanel::Yum::Vars

=head1 SYNOPSIS

    Cpanel::Yum::Vars::install();

    Cpanel::Yum::Vars::uninstall();

=head1 DESCRIPTION

Different YUM-based Linux distributions assign certain different
values to YUM’s built-in variables. C<$releasever>, for example,
is not always C<6> or C<7>.

To accommodate cases where we need for YUM to know the major CentOS
release to which the system’s installed Linux distribution corresponds,
we maintain a set of YUM variables on the system. This module interfaces
with those variables and their on-disk storage.

Right now, the only variable we provide to yum is 'cp_centos_major_version'

=head1 FUNCTIONS

=head2 install

Puts the variable files in place for use with cPanel provided repos.

=cut

our $yum_dir = '/etc/yum/vars';

sub install {
    return unless Cpanel::OS::is_yum_based();

    Cpanel::FileUtils::Write::overwrite( "$yum_dir/cp_centos_major_version", Cpanel::OS::major() );    ## no critic(Cpanel::CpanelOS)

    return;
}

=head2 uninstall

Removes the variable files.

=cut

sub uninstall {
    return unless Cpanel::OS::is_yum_based();

    unlink "$yum_dir/cp_centos_major_version";

    return;
}

1;
