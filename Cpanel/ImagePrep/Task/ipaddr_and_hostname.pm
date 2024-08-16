package Cpanel::ImagePrep::Task::ipaddr_and_hostname;

#                                      Copyright 2024 WebPros International, LLC
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited.

use cPstrict;

use parent 'Cpanel::ImagePrep::Task';
use Cpanel::Imports;
use Try::Tiny;

use Cpanel::Config::LoadWwwAcctConf  ();
use Cpanel::Domain::ExternalResolver ();
use Cpanel::FileUtils::Modify        ();
use Cpanel::Hostname                 ();
use Cpanel::InterfaceLock::Remove    ();
use Cpanel::SafeDir::RM              ();
use Cpanel::ServerTasks              ();
use Cpanel::SSLCerts                 ();
use Whostmgr::Hostname::History      ();

use constant DISABLE_SERVICES => qw(cpanel dnsadmin httpd dovecot);

=head1 NAME

Cpanel::ImagePrep::Task::ipaddr_and_hostname - An implementation subclass of Cpanel::ImagePrep::Task. See parent class for interface.

=cut

sub _description {
    return <<EOF;
Handle the server-specific configuration related to IP address and hostname.

This is a large catch-all task that affects multiple configuration files
and services. These are combined into a single task because they are all
related and need to run in a certain order relative to one another. These
tasks also need to be done before various other tasks run.
EOF
}

sub _type { return 'non-repair only' }

=head2 PRE ACTIONS

Clear configurations related to the server IP address and/or hostname.

=cut

sub _pre {
    my ($self) = @_;

    for my $disable_service ( DISABLE_SERVICES() ) {
        $self->common->disable_service($disable_service);
    }

    $self->common->_touch('/var/cpanel/cpinit-ip.wait');

    Cpanel::FileUtils::Modify::match_replace(
        '/etc/wwwacct.conf',

        # Match only ADDR, ADDR6, HOST, NS, NS2, NS3, NS4 up to the end of the
        # line, including the newline char, with optional space after the key
        # when the value is empty
        [ { match => qr/^(?:ADDR6?|HOST|NS[2-4]?)(?:\s*|\s+\S*)\R/m, replace => q{} } ]
    );

    $self->loginfo('Clearing wwwacct.conf cache ...');
    Cpanel::Config::LoadWwwAcctConf::reset_caches();

    my @cpnat_files = $self->common->_glob('/var/cpanel/cpnat*');
    $self->common->_unlink($_) for @cpnat_files;

    $self->common->_rename_to_backup('/var/cpanel/ssl');    # will be regenerated as part of ensure_hostname_resolves

    $self->loginfo('Deleting /var/cpanel/domain_keys ...');
    Cpanel::SafeDir::RM::safermdir('/var/cpanel/domain_keys');

    $self->loginfo('Clearing hostname history ...');
    Whostmgr::Hostname::History::clear();

    return $self->PRE_POST_OK;
}

=head2 POST ACTIONS

Regenerate configurations related to the server IP address and/or hostname.

=cut

sub _post {
    my ($self) = @_;

    my @disabled_services = DISABLE_SERVICES();

    my $cpnat_exception;
    try {
        $self->common->run_command('/usr/local/cpanel/scripts/build_cpnat');
        $self->loginfo('Rebuilt cpnat');
    }
    catch {
        $cpnat_exception = $_;
    };
    if ($cpnat_exception) {
        if ( $self->common->_exists('/var/cpanel/cpnat') ) {
            $self->loginfo('Rebuilt cpnat with one or more errors (see /usr/local/cpanel/logs/error_log)');
        }
        else {
            $self->loginfo("Failed to rebuild cpnat: $cpnat_exception");
            return $self->PRE_POST_FAILED;
        }
    }

    # We want dnsadmin to be running (and to create its socket) when ensure_hostname_resolve runs to avoid delays
    # and warnings related to checking the socket.
    @disabled_services = grep { $_ ne 'dnsadmin' } @disabled_services;
    $self->common->enable_service( 'dnsadmin', { force => 1 } );

    Cpanel::InterfaceLock::Remove::remove_lock('UpdateHostname');

    if ( try { Cpanel::Domain::ExternalResolver::domain_is_on_local_server( Cpanel::Hostname::gethostname(1) ) } ) {
        $self->loginfo('Hostname: The hostname already resolves correctly.');

        # Even if the hostname is already correct, the configuration should be synchronized by set_hostname because
        # it is almost certainly different from the hostname used to create the snapshot.
        $self->common->run_command( '/usr/local/cpanel/bin/set_hostname', Cpanel::Hostname::gethostname() );
    }
    else {
        # Update the 'cpanel' SSL certificate early so that it will exist when when httpd
        # configuration is validated during the hostname change.
        $self->_generate_default_ssl_certs('cpanel');

        $self->common->run_command( '/usr/local/cpanel/scripts/ensure_hostname_resolves', '--yes' );

        # The gethostname call in this conditional cached the old hostname in memory, and it has changed. Clear and
        # update the in-memory hostname cache with the new hostname for later use, such as by
        # createDefaultSSLFiles.
        Cpanel::Hostname::gethostname(1);
    }

    $self->common->run_command( '/usr/local/cpanel/scripts/mkwwwacctconf', '--force', '--inherit' );
    $self->loginfo('Rebuilt wwwacct.conf');

    # FTP is disabled by default and so may not receive a signed certificate even upon success, but we still
    # need the default self-signed certificate for it or the FTP server installation will fail later. For
    # other services, we will also generate default certificates here in case the signed certificate retrieval
    # fails. This does not include Apache, which is handled separately.
    $self->_generate_default_ssl_certs();

    $self->common->run_command('/usr/local/cpanel/scripts/rebuildhttpdconf');
    $self->loginfo('Rebuilt httpd.conf');

    # Enable and start httpd before attempting to obtain signed certificates so HTTP DCV can work.
    @disabled_services = grep { $_ ne 'httpd' } @disabled_services;
    $self->common->enable_service('httpd');

    # Even if the server hostname is already resolving correctly, we want to check whether the service
    # certificates are up to date or not because the most recent hostname change may have been done outside of
    # cPanel & WHM's control. If 'ensure_hostname_resolves' was recently run, it also was not able to obtain a
    # signed certificate because httpd was not ready until now.
    $self->loginfo('Attempting to obtain signed SSL certificates.');
    try {
        $self->common->run_command(qw(/usr/local/cpanel/bin/checkallsslcerts --verbose))
    }
    catch {
        $self->loginfo('checkallsslcerts failed; queueing a task to retry in the background in 60 seconds...');
        try { Cpanel::ServerTasks::schedule_task( ['SSLTasks'], 60, 'checkallsslcerts --retry' ) };
    };

    for my $enable_service (@disabled_services) {
        $self->common->enable_service($enable_service);
    }

    $self->common->_unlink('/var/cpanel/cpinit-ip.wait');
    $self->loginfo('Removed cpinit-ip.wait');

    return $self->PRE_POST_OK;
}

sub _deps { return qw(license); }    # AutoSSL requires the license step to be done

sub _generate_default_ssl_certs {
    my ( $self, @services ) = @_;
    @services = sort keys %{ Cpanel::SSLCerts::getSSLServiceList() } unless @services;
    for my $service (@services) {
        my ( $default_files_status, $default_files_reason ) = Cpanel::SSLCerts::createDefaultSSLFiles( service => $service, skip_nonselfsigned => 1 );
        if ( !$default_files_status ) {
            $self->loginfo("createDefaultSSLFiles() for '$service' did not succeed: $default_files_reason");
            $self->loginfo('Continuing anyway');
        }
        else {
            $self->loginfo("Regenerated '$service' service certificates.");
        }
    }
    return;
}

1;
