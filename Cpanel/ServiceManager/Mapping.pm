package Cpanel::ServiceManager::Mapping;

# cpanel - Cpanel/ServiceManager/Mapping.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Config::LoadCpConf ();

=encoding utf-8

=head1 NAME

Cpanel::ServiceManager::Mapping - Provide mapping from service name to ServiceManager name

=head1 SYNOPSIS

    use Cpanel::ServiceManager::Mapping ();

    my $servicemanager_module = get_service_name_to_service_manager_module_map('imap');


=head1 DESCRIPTION

This maps the service name provided in by Whostmgr::Services and Cpanel::Services
to the Cpanel::ServiceManager module.

=cut

#This translates a service name as Cpanel::Services refers to it
#into a name as Cpanel::ServiceManager recognizes it. Note that
#Dovecot is represented here as LMTP since that service is always on.
use constant SERVICE_NAME_FOR_SERVICE_MANAGER__KV => (
    postgres       => 'postgresql',
    rsyslogd       => 'rsyslog',
    lmtp           => 'dovecot',
    pop3           => 'dovecot',
    imap           => 'dovecot',
    'exim-altport' => 'exim',

    #We add whichever FTP service is relevant in production
);

#sigh … this gets run from the test
sub _augment_service_manager_hashref_with_ftpd {
    my ($sm_hr) = @_;

    my $cpconf = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();
    if ( $cpconf->{'ftpserver'} eq 'pure-ftpd' ) {
        $sm_hr->{'ftpd'} = 'pureftpd';
    }
    elsif ( $cpconf->{'ftpserver'} eq 'proftpd' ) {
        $sm_hr->{'ftpd'} = 'proftpd';
    }
    elsif ( $cpconf->{'ftpserver'} eq 'disabled' ) {
        $sm_hr->{'ftpd'} = 'disabled';
    }
    else {
        warn "Unknown FTP server in cpanel config: “$cpconf->{'ftpserver'}”";
    }

    return;
}

=head2 get_service_name_to_service_manager_module_map()

Returns a hashref of service names as keys and
Cpanel::ServiceManager module names as values

=cut

sub get_service_name_to_service_manager_module_map {

    #This translates a service name as Cpanel::Services refers to it
    #into a name as Cpanel::ServiceManager recognizes it. Note that
    #Dovecot is represented here as LMTP since that service is always on.
    my %SERVICE_NAME_FOR_SERVICE_MANAGER = SERVICE_NAME_FOR_SERVICE_MANAGER__KV();

    _augment_service_manager_hashref_with_ftpd(
        \%SERVICE_NAME_FOR_SERVICE_MANAGER,
    );

    return \%SERVICE_NAME_FOR_SERVICE_MANAGER;

}

1;
