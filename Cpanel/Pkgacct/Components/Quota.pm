package Cpanel::Pkgacct::Components::Quota;

# cpanel - Cpanel/Pkgacct/Components/Quota.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use parent 'Cpanel::Pkgacct::Component';

use strict;
use warnings;
use Cpanel::Config::LoadCpUserFile ();
use Cpanel::FileUtils::Write       ();
use Cpanel::Quota::Common          ();

sub perform {
    my ($self) = @_;

    my $work_dir = $self->get_work_dir();
    my $user     = $self->get_user();

    my $cpuser_ref = Cpanel::Config::LoadCpUserFile::loadcpuserfile($user);
    my $quota      = $cpuser_ref->{'DISK_BLOCK_LIMIT'} || 0;
    $quota /= $Cpanel::Quota::Common::MEGABYTES_TO_BLOCKS;

    Cpanel::FileUtils::Write::overwrite( "$work_dir/quota", $quota, 0600 );
    return 1;
}

1;
