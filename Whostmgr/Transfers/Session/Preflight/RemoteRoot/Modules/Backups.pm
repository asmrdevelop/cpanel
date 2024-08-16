package Whostmgr::Transfers::Session::Preflight::RemoteRoot::Modules::Backups;

# cpanel - Whostmgr/Transfers/Session/Preflight/RemoteRoot/Modules/Backups.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;
use Whostmgr::Config::Backup::System::Backups ();
use parent 'Whostmgr::Transfers::Session::Preflight::RemoteRoot::Base';

use constant _BACKUP_NAMESPACE => 'cpanel::system::backups';

use constant _ANALYSIS_KEY_SUFFIX => 'INFO';

# See /usr/local/cpanel/Whostmgr/Transfers/Session/Items/Backups* for how we
# backup and restore the data

sub _parse_analysis_commands {
    my ( $self, $remote_data ) = @_;

    my $module_name = $self->_module_name();

    # Take the output of the --query-module-info in get_analysis_commands() for parsing response data out of
    my $query   = $remote_data->{ $self->_analysis_key() } || '';
    my $version = "";

    my @lines = split( /\n/, $query );
    foreach my $line (@lines) {
        if ( $line =~ m/^cpanel::system::backups: Backups_Version=(.+)$/ ) {
            $version = $1;
        }
    }

    # Get local version
    my $local_version = Whostmgr::Config::Backup::System::Backups->query_module_info();
    $local_version =~ s/Backups_Version=//;

    return {
        'Local_' . $module_name . '_Version'  => $local_version,
        'Remote_' . $module_name . '_Version' => $version,
    };
}

# For some reason this isn’t translated … ?
use constant name => 'Backups';

1;
