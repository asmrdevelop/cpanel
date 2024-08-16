package Cpanel::Backup::Utility::Legacy;

# cpanel - Cpanel/Backup/Utility/Legacy.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Autodie ('exists');

our $legacy_conf = '/etc/cpbackup.conf';

=encoding utf-8

=head1 NAME

Cpanel::Backup::Utility::Legacy - Functions for dealing with legacy backups

=head1 SYNOPSIS

    use Cpanel::Backup::Utility::Legacy;

    if ( Cpanel::Backup::Utility::Legacy::check_legacy_backup_exist() ) {
        # ... do legacy backup things
    }

=cut

=head2 check_legacy_backup_exist

Summary...

=over 2

=item Input

None

=item Output

=over 3

=item 0: The legacy backup config does not exist

=item 1: The legacy backup config exists

=back

=back

=cut

sub check_legacy_backup_exist {
    return Cpanel::Autodie::exists($legacy_conf) ? 1 : 0;
}

1;
