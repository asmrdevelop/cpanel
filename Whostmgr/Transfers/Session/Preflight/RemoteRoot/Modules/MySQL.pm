package Whostmgr::Transfers::Session::Preflight::RemoteRoot::Modules::MySQL;

# cpanel - Whostmgr/Transfers/Session/Preflight/RemoteRoot/Modules/MySQL.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;
use Whostmgr::Config::Backup::System::Mysql ();

use parent 'Whostmgr::Transfers::Session::Preflight::RemoteRoot::Base';

use constant _BACKUP_NAMESPACE => 'cpanel::system::mysql';

use constant _ANALYSIS_KEY_SUFFIX => 'VERSION';

# See /usr/local/cpanel/Whostmgr/Transfers/Session/Items/MySQL* for how we
# backup and restore the data

sub _parse_analysis_commands {
    my ( $self, $remote_data ) = @_;
    my ( @warnings, @errors );
    my $module = $self->_module_name();

    # Get remote version
    my $query       = $remote_data->{ $self->_analysis_key() } || '';
    my $rem_version = '';

    my @lines = split( /\n/, $query );
    foreach my $line (@lines) {
        if ( $line =~ m/^cpanel::system::mysql:\ MySQL_Version=(.+)$/ ) {
            $rem_version = $1;
        }
    }
    my $rem_db_type = 'MySQL';
    if ( $rem_version && $rem_version > 9.0 ) {
        $rem_db_type = 'MariaDB';
    }

    # Get local version
    my $local_version = Whostmgr::Config::Backup::System::Mysql->query_module_info();
    $local_version =~ s/MySQL_Version=//;
    my $local_db_type = 'MySQL';
    if ( $local_version && $local_version > 9.0 ) {
        $local_db_type = 'MariaDB';
    }

    # Check to see what known conflicting states we might be in and advise user
    if ( $rem_db_type eq 'MariaDB' and $local_db_type eq 'MySQL' ) {
        push( @errors, "Downgrading server type $local_db_type $local_version to $rem_db_type $rem_version is not supported here." );

    }
    elsif ( $local_db_type eq $rem_db_type && $local_version && $rem_version && $local_version > $rem_version ) {
        push( @errors, "Downgrading databases from version $rem_db_type $rem_version to $local_db_type $local_version is not supported here. Please upgrade the remote server first." );
    }

    return {
        'warnings'       => \@warnings     || '',
        'errors'         => \@errors       || '',
        'Remote_Version' => $rem_version   || '',
        'Remote_Type'    => $rem_db_type   || '',
        'Local_Version'  => $local_version || '',
        'Local_Type'     => $local_db_type || ''
    };
}

sub name {
    my ($self) = @_;
    return $self->_locale()->maketext("Database Server");
}

1;
