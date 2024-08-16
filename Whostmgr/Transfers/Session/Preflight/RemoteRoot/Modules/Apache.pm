package Whostmgr::Transfers::Session::Preflight::RemoteRoot::Modules::Apache;

# cpanel - Whostmgr/Transfers/Session/Preflight/RemoteRoot/Modules/Apache.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;
use Whostmgr::Config::Backup::Easy::Apache ();
use Storable                               qw(nfreeze thaw);
use MIME::Base64;
use Cpanel::Logger ();

use parent 'Whostmgr::Transfers::Session::Preflight::RemoteRoot::Base';

use constant _BACKUP_NAMESPACE => 'cpanel::easy::apache';

use constant _ANALYSIS_KEY_SUFFIX => 'VERSION';

my $logger = Cpanel::Logger->new();

# [ { 'key' => $self->module_name() . '_VERSION',        'shell_safe_arguments' => '', 'shell_safe_command' => '[ if [ -e /etc/cpanel/ea4/is_ea4 ]; then /bin/echo "EasyApache 4"; else /bin/echo "EasyApache 3"; fi ]' } ],

sub _parse_analysis_commands {
    my ( $self, $remote_data ) = @_;
    my ( @warnings, @errors );

    my $module_name = $self->_module_name();

    # Get remote info
    my $query              = $remote_data->{ $self->_analysis_key() } || '';
    my $rem_EA_version     = "";
    my $rem_Apache_version = "";
    my $blocker_ar;

    my %rem_blockers;

    # parse output for EA and httpd version, as well as any blocker data from the migration blocker system
    my @lines = split( /\n/, $query );
    foreach my $line (@lines) {
        if ( $line =~ m/EAVERSION:\s+(.+)$/ ) {
            $rem_EA_version = $1;
        }
        elsif ( $line =~ m/HTTPDVERSION:\s+(.+)$/ ) {
            $rem_Apache_version = $1;
        }
        elsif ( $line =~ m/BLOCKER\-\[(.+)\]-v(\d+):\s+(.+)$/ ) {
            my $blocker_name         = $1;
            my $blocker_version      = $2;
            my $blocker_encoded_hash = $3;
            $rem_blockers{$blocker_name}{'name'}    = $blocker_name;
            $rem_blockers{$blocker_name}{'version'} = $blocker_version;
            $rem_blockers{$blocker_name}{'content'} = $blocker_encoded_hash;
        }
    }

    foreach my $rem_block ( keys %rem_blockers ) {
        my $rem_name = $rem_blockers{$rem_block}{'name'};
        $logger->info("Found remote module $rem_name");
        $rem_blockers{$rem_block}->{'content'} =~ s/__NEWLINE__/\n/g;
        my $frozen_blocker = MIME::Base64::decode_base64( $rem_blockers{$rem_block}->{'content'} );
        my %thawed_blocker = %{ thaw($frozen_blocker) };

        # Replace the frozen, base64 encoded content with the actual module text
        $rem_blockers{$rem_block}->{'data'} = \%thawed_blocker;
    }

    # Get local info
    my $local_version_data   = Whostmgr::Config::Backup::Easy::Apache->query_module_info();
    my $local_EA_version     = $local_version_data->{'EAVERSION'};
    my $local_Apache_version = $local_version_data->{'HTTPDVERSION'};

    return {
        'warnings'             => \@warnings            || '',
        'errors'               => \@errors              || '',
        'Remote_EA_Version'    => $rem_EA_version       || '',
        'Remote_HTTPD_Version' => $rem_Apache_version   || '',
        'Local_EA_Version'     => $local_EA_version     || '',
        'Local_HTTPD_Version'  => $local_Apache_version || '',
        'Blocker_Data'         => $blocker_ar           || ''
    };
}

# The UI actually expects this name in code.
use constant name => 'Easy Apache';

1;
