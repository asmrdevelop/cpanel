package Whostmgr::Transfers::Session::Preflight::RemoteRoot::Modules::Exim;

# cpanel - Whostmgr/Transfers/Session/Preflight/RemoteRoot/Modules/Exim.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;
use Whostmgr::Config::Backup::SMTP::Exim ();
use parent 'Whostmgr::Transfers::Session::Preflight::RemoteRoot::Base';

use constant _BACKUP_NAMESPACE => 'cpanel::smtp::exim';

use constant _ANALYSIS_KEY_SUFFIX => 'INFO';

# See /usr/local/cpanel/Whostmgr/Transfers/Session/Items/Exim* for how we
# backup and restore the data

sub _parse_analysis_commands {
    my ( $self, $remote_data ) = @_;

    my $module_name = $self->_module_name();

    # Get remote info
    my $query              = $remote_data->{ $self->_analysis_key() } || '';
    my $rem_version        = '';
    my $rem_config_version = '';

    my @lines = split( /\n/, $query );
    foreach my $line (@lines) {
        if ( $line =~ m/EXIM:\s+(.+)$/ ) {
            $rem_version = $1;
            $rem_version =~ s/["']//g;    # strip common shell quoting from possible processing done by get_analysis_commands()
        }
        elsif ( $line =~ m/EXIM_CONFIG:\s+(.+)$/ ) {
            $rem_config_version = $1;
            $rem_config_version =~ s/["']//g;    # strip common shell quoting from possible processing done by get_analysis_commands()
        }
    }

    $rem_version        = '' if !defined $rem_version;
    $rem_config_version = '' if !defined $rem_config_version;

    # Get local info
    my $local_version_data = Whostmgr::Config::Backup::SMTP::Exim->query_module_info();

    return {
        'Remote_' . $module_name . '_Version'               => $rem_version,
        'Remote_' . $module_name . '_Configuration_Version' => $rem_config_version,
        'Local_' . $module_name . '_Version'                => $local_version_data->{'EXIM'},
        'Local_' . $module_name . '_Configuration_Version'  => $local_version_data->{'EXIM_CONFIG'}
    };
}

use constant name => 'Exim';

1;
