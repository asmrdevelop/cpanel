package Cpanel::Config::Services;

# cpanel - Cpanel/Config/Services.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Cpanel::Services::Enabled ();

my %disable_files = (
    'dns'  => '/etc/nameddisable',
    'ftp'  => '/etc/ftpddisable',
    'mail' => '/etc/imapdisable'
);

sub is_enabled { goto &service_enabled; }

sub service_enabled {
    my $service = shift;
    if ( !$service ) {
        require Cpanel::Logger;
        my $logger = Cpanel::Logger->new();
        $logger->warn('No service specified to determine if enabled');
        return wantarray ? ( 0, 'No service specified to determine if enabled' ) : 0;
    }

    my $disabled_service_name;
    my $srv_en = 1;                         # default to enabled
    my @srvcs  = split( /\,/, $service );
    my $msg;
    foreach my $srvc (@srvcs) {

        # Warning : is_enabled returns 1 if service is enabled, 0 if disabled, -1 if unknown
        # we consider that a service is enabled when we cannot know its state ( accept -1 and 1 )
        #   used for at least postgres and postmaster services
        unless ( Cpanel::Services::Enabled::is_enabled($srvc) ) {
            $disabled_service_name = $srvc;
            $msg                   = defined( $disable_files{$srvc} ) ? $disable_files{$srvc} : '/etc/' . $disabled_service_name . 'disable';

            # if disabled, set it so
            $srv_en = 0;
            last;
        }
    }

    if ( $srv_en == 0 ) {
        return wantarray ? ( 0, $msg ) : 0;
    }
    else {
        return wantarray ? ( 1, $service . ' is enabled' ) : 1;
    }
}

1;
