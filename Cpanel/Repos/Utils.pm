package Cpanel::Repos::Utils;

# cpanel - Cpanel/Repos/Utils.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::OS            ();
use Cpanel::Binaries::Yum ();

=encoding utf-8

=head1 NAME

Cpanel::Repos::Utils - Utilities for working with repos

=head1 SYNOPSIS

    use Cpanel::Repos::Utils;

    Cpanel::Repos::Utils::post_install();

=head2 post_install()

Perform post install tasks after installing a new repo.

Currently the sole post install task is to
clear the fastestmirror plugin cache so that the next
time we do a yum call we do not fallback to roundrobin.

=cut

sub post_install() {

    return unless Cpanel::OS::can_clean_plugins_repo();

    require Cpanel::Binaries::Yum;

    my $result = Cpanel::Binaries::Yum->new->cmd( 'clean', 'plugins' );
    warn $result->{'output'} if $result->{'status'};

    return 1;

}

1;
