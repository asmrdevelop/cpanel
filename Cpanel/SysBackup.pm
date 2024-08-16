
# cpanel - Cpanel/SysBackup.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::SysBackup;

use Cpanel::Config::Backup ();

sub fetchbackupdir {
    my $backup_conf_ref = Cpanel::Config::Backup::load();
    return $backup_conf_ref->{'BACKUPDIR'};
}

1;
