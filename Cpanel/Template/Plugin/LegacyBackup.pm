package Cpanel::Template::Plugin::LegacyBackup;

# cpanel - Cpanel/Template/Plugin/LegacyBackup.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent 'Template::Plugin';

use Cpanel::Cgi ();
use Try::Tiny;
use Cpanel::SafeRun::Object ();

=head1 NAME

Cpanel::Template::Plugin::LegacyBackup

=head1 DESCRIPTION

Wrapper for legacy backup calls

=head1 SYNOPSIS

    USE LegacyBackup;

    IF LegacyBackup.legacy_backups_enabled;
        SET myvar = LegacyBackup.list_legacy_backups;
    END;

=head2 legacy_backups_enabled()

Check if legacy backups are enabled for the user. We use UAPI Variables::get_user_information to retrieve this status.

=head3 RETURNS

string - 1 if legacy backups are enabled, 0 if not (or if there is no return from Variables::get_user_information).

=cut

sub legacy_backups_enabled {
    require Cpanel::API;
    my $result = Cpanel::API::execute( 'Variables', 'get_user_information', { 'name' => 'legacy_backup_enabled' } );

    die $result->errors_as_string() if !$result->status();

    return $result->data->{'legacy_backup_enabled'} // 0;
}

=head2 list_legacy_backups()

Provides an HTML-formatted list of available legacy backups to download.

The output is determined by /usr/local/cpanel/bin/backupwrap.

=head3 RETURNS

string - the output of /usr/local/cpanel/bin/backupwrap.

=cut

sub list_legacy_backups {
    my $result;

    try {
        $result = Cpanel::SafeRun::Object->new_or_die(
            program => '/usr/local/cpanel/bin/backupwrap',
            args    => ['LIST']
        )->stdout();
    }
    catch {
        warn "Failed to fetch a list of backups: $_";
        $result = '';
    };

    if ( $ENV{'cp_security_token'} ) {
        $result =~ s[action="/getsysbackup/][action="$ENV{'cp_security_token'}/getsysbackup/]g;
    }

    return $result;
}

=head2 get_backup_link()

Provides a relative, cpsrvd-aware path to the most recent user backup.

The output is determined by Cpanel::Cgi::backuplink.

=head3 RETURNS

string - the output of Cpanel::Cgi::backuplink.

=cut

sub get_backup_link {
    return Cpanel::Cgi::backuplink();
}

1;
