package Whostmgr::Transfers::Session::Preflight::RemoteRoot::Modules::Themes;

# cpanel - Whostmgr/Transfers/Session/Preflight/RemoteRoot/Modules/Themes.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;
use Whostmgr::Config::Backup::UI::Themes ();
use parent 'Whostmgr::Transfers::Session::Preflight::RemoteRoot::Base';

use constant _BACKUP_NAMESPACE    => 'cpanel::ui::themes';
use constant _ANALYSIS_KEY_SUFFIX => 'INFO';

# See /usr/local/cpanel/Whostmgr/Transfers/Session/Items/Themes* for how we
# backup and restore the data

sub _parse_analysis_commands {
    my ( $self, $remote_data ) = @_;

    my $module_name = $self->_module_name();

    # Get remote info
    my $query       = $remote_data->{ $self->_analysis_key() } || '';
    my $rem_version = '';

    my @lines = split( /\n/, $query );
    foreach my $line (@lines) {
        if ( $line =~ m/THEMES:\s+(.+)$/ ) {
            $rem_version = $1;
            $rem_version =~ s/["']//g;    # strip common shell quoting from possible processing done by get_analysis_commands()
        }
    }

    $rem_version = '' if !defined $rem_version;

    # Get local info
    my $local_version_data = Whostmgr::Config::Backup::UI::Themes->query_module_info();

    return {
        'Remote_' . $module_name . '_Version' => $rem_version,
        'Local_' . $module_name . '_Version'  => $local_version_data->{'THEMES'},
    };
}

sub name {
    my ($self) = @_;
    return $self->_locale()->maketext("User Interface Themes");
}

1;
