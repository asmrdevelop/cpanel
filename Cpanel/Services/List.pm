package Cpanel::Services::List;

# cpanel - Cpanel/Services/List.pm                 Copyright 2024 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::Chkservd::Config          ();
use Cpanel::Chkservd::Config::Drivers ();
use Cpanel::Debug                     ();
use Cpanel::Server::Type              ();

=head1 NAME

Cpanel::Services::List

=cut

#Despite the name, this returns either a list of key/value pairs
#or a hashref.
sub get_service_list {
    my $services = _get_services();
    return wantarray ? %$services : $services;
}

sub get_name {
    my $service = shift;
    return unless defined $service;

    my $services = _get_services();
    return          if !exists $services->{$service};
    return $service if !exists $services->{$service}->{'name'};
    return $services->{$service}->{'name'};
}

=head2 canonicalize_service($service, $enabled, $monitored_status_for)

Fix up the service attributes for the given service.  This is a generic helper
for exim-altport and any future services that need similar help.

C<$monitored_status_for> is a hashref mapping services to monitored states.
Such a hashref can be acquired from C<Cpanel::Chkservd::Manage::getmonitored>.

Returns a hashref of the following:

=over 4

=item B<service>

The service name as chkservd understands it

=item B<enabled>

Whether the service is enabled

=item B<monitored>

Whether the service is monitored

=item B<settings>

A hashref of settings if applicable; otherwise, undef

=back

=cut

sub canonicalize_service {
    my ( $service, $enabled, $monitored_status_for ) = @_;

    unless ( $service eq 'exim-altport' ) {
        return {
            'service'   => $service,
            'enabled'   => $enabled,
            'monitored' => $monitored_status_for->{$service},
        };
    }

    my @services;
    if ( opendir my $chkservd, $Cpanel::Chkservd::Config::chkservd_dir ) {
        @services = grep { !m{-cpanelsync$} && !m{\.rpm[^\.]+$} } readdir $chkservd;
        closedir $chkservd;
    }

    my $settings = {
        'name'  => 'exim-altportnum',
        'size'  => 30,
        'value' => 26,
    };

    foreach my $service (@services) {
        if ( $service =~ /^exim-([0-9\,]+)/ ) {
            $settings->{'value'} = $1;
            my $monitored = exists $monitored_status_for->{$service} && $monitored_status_for->{$service} == 1 ? 1 : 0;
            return {
                'service'   => $service,
                'enabled'   => 1,
                'monitored' => $monitored,
                'settings'  => $settings,
            };
        }
    }

    return {
        'service'   => $service,
        'enabled'   => 0,
        'monitored' => 0,
        'settings'  => $settings,
    };
}

our $SERVS;

sub get_default_service_list {
    my $locale     = _get_locale();
    my $cpconf_ref = _get_cpconf();
    my $is_wp2     = Cpanel::Server::Type::is_wp_squared() ? 1 : 0;

    $SERVS = {
        'apache_php_fpm' => {
            'name'         => $locale->maketext('[asis,PHP-FPM] service for [asis,Apache]'),
            'hide_from_ui' => 1,
        },
        'clamd' => {
            'name'        => $locale->maketext('[asis,ClamAV] Daemon'),
            'description' => $locale->maketext('[asis,ClamAV] Virus Scanner'),
        },
        'crond' => {
            'name'           => $locale->maketext('[asis,Cron] Daemon'),
            'always_enabled' => 1,
        },
        'cpanellogd' => {
            'name' => $locale->maketext('[asis,cPanel] Log and Bandwidth Processor'),
        },
        'cpdavd' => {
            'name'         => $locale->maketext('[asis,cPanel] [asis,DAV] Daemon'),
            'description'  => $locale->maketext('WebDisk, Calendars, and Contacts services for [asis,cPanel]'),
            'hide_from_ui' => _is_cpdavd_needed(),
        },
        'cphulkd' => {
            'name'        => $locale->maketext('[asis,cPHulk] Daemon'),
            'description' => $locale->maketext('[asis,cPHulk] Brute Force Protection'),
        },
        'cpsrvd' => {
            'name'           => $locale->maketext('[asis,cPanel] Daemon'),
            'always_enabled' => 1,
        },
        'cpanel_php_fpm' => {
            'name'           => $locale->maketext('[asis,PHP-FPM] service for [asis,cPanel] Daemons'),
            'skip_dnsonly'   => 1,
            'hide_from_ui'   => $is_wp2,
            'required_roles' => [qw(WebServer)],
        },
        'cpgreylistd' => {
            'name'           => $locale->maketext('[asis,cPanel] [asis,Greylisting] Daemon'),
            'skip_dnsonly'   => 1,
            'required_roles' => [qw(MailReceive)],
        },
        'p0f' => {
            'name' => $locale->maketext('Passive [output,abbr,OS,Operating System] Fingerprinting Daemon'),
        },
        'dnsadmin' => {
            'name'           => $locale->maketext('[asis,cPanel] [output,abbr,DNS,Domain Name System] Admin Cache'),
            'description'    => $locale->maketext('[asis,cPanel] [output,abbr,DNS,Domain Name System] Admin Cache Service'),
            'always_enabled' => 1,
            'required_roles' => [qw(DNS)]
        },
        'exim' => {
            'name'           => $locale->maketext('[asis,Exim] Mail Server'),
            'description'    => $locale->maketext('[output,abbr,SMTP,Simple Mail Transport Protocol] Server'),
            'required_roles' => [qw(MailSend MailReceive)],
        },
        'exim-altport' => {
            'name'           => $locale->maketext('[asis,Exim] Mail Server (on another port)'),
            'note'           => $locale->maketext('Useful for providers that block port 25 (multiple comma-delimited ports may be added).'),
            'description'    => $locale->maketext('Allow [asis,exim] to listen on a port other than 25, 465, and 587.'),
            'required_roles' => [qw(MailSend MailReceive)],
        },
        'ftpd' => {
            'name'           => $locale->maketext('[output,abbr,FTP,File Transfer Protocol] Server'),
            'required_roles' => [qw(FTP)],
        },
        'httpd' => {
            'name'           => $locale->maketext('[asis,Apache] Web Server'),
            'description'    => $locale->maketext('Web Server'),
            'required_roles' => [qw(WebServer)],
            'always_enabled' => $is_wp2,
        },
        'imap' => {
            'name'           => $locale->maketext('[output,abbr,IMAP,Internet Mail Access Protocol] Server'),
            description      => $locale->maketext('[asis,Dovecot] [output,abbr,IMAP,Internet Mail Access Protocol] Server'),
            'skip_dnsonly'   => 1,
            'required_roles' => [qw(MailReceive)]
        },
        'lmtp' => {
            'name'           => $locale->maketext('[output,abbr,LMTP,Local Mail Transport Protocol] Server'),
            'description'    => $locale->maketext('[asis,Dovecot] [output,abbr,LMTP,Local Mail Transport Protocol] Server'),
            'always_enabled' => 1,
            'required_roles' => [qw(MailLocal)],
        },
        'pop' => {
            'name'           => $locale->maketext('[output,abbr,POP3,Post Office Protocol 3] Server'),
            'description'    => $locale->maketext('[asis,Dovecot] [output,abbr,POP3,Post Office Protocol 3] Server'),
            'skip_dnsonly'   => 1,
            'required_roles' => [qw(MailReceive)],
        },
        'ipaliases' => {
            'name' => $locale->maketext('[output,abbr,IP,Internet Protocol] Aliases'),
        },
        'mailman' => {
            'name'           => $locale->maketext('[asis,Mailman]'),
            'description'    => $locale->maketext('Mailing List Manager'),
            'required_roles' => [qw(MailSend)]
        },
        'mysql' => {
            'name'           => $locale->maketext('Database Server'),
            'description'    => $locale->maketext('[asis,MySQL] Database Server'),
            'always_enabled' => $is_wp2 || ( $cpconf_ref->{'roundcube_db'} eq 'mysql' ) ? 1 : 0,
            'required_roles' => [qw<MySQL>],
        },
        'named' => {
            'name'                 => $locale->maketext('[output,abbr,DNS,Domain Name System] Server'),
            'description'          => $locale->maketext('Berkeley Name Server Daemon ([asis,BIND])'),
            'description_powerdns' => $locale->maketext('[asis,PowerDNS]'),
            'description_disabled' => $locale->maketext( 'You have disabled the [output,abbr,DNS,Domain Name System] Server. Visit the [output,url,_1,Nameserver Selection] page to enable this service.', '../scripts/nameserverconfig' ),
            'required_roles'       => [qw(DNS)],
        },
        'nginx' => {
            'name'           => $locale->maketext('[asis,NGINX] Server'),
            'description'    => $locale->maketext('[asis,NGINX] Web Server'),
            'always_enabled' => $is_wp2,
        },
        'postgresql' => {
            'name'           => $locale->maketext('[asis,PostgreSQL] Server'),
            'description'    => $locale->maketext('[asis,PostgreSQL] Database Server'),
            'required_roles' => [qw(Postgres)],
        },
        'queueprocd' => {
            'name'           => $locale->maketext('[asis,TaskQueue] Processor'),
            'description'    => $locale->maketext('[asis,TaskQueue] Processing Server'),
            'always_enabled' => 1,
        },
        'rsyslogd' => {
            'name'        => $locale->maketext('[asis,rsyslog] System Logger Daemon'),
            'description' => $locale->maketext('Enhanced System Logger Daemon'),
        },
        'spamd' => {
            'name'           => $locale->maketext('[asis,Apache SpamAssassin™]'),
            'description'    => $locale->maketext('[asis,SpamAssassin] Server (if you choose to disable this, you should disable [asis,SpamAssassin] in the [asis,Tweak Settings] interface as well)'),
            'skip_dnsonly'   => 1,
            'required_roles' => [qw(MailReceive)],
        },
        'sshd' => {
            'name'        => $locale->maketext('[output,abbr,SSH,Secure Shell] Daemon'),
            'description' => $locale->maketext('Secure Shell Daemon'),
        },
        'nscd' => {
            'name' => $locale->maketext('Name Service Cache Daemon'),
        },
        'syslogd' => {
            'name'        => $locale->maketext('[asis,syslog] System Logger Daemon'),
            'description' => $locale->maketext('System Logger Daemon'),
        },
        'tailwatchd' => {
            'name'           => $locale->maketext('[asis,TailWatch] Daemon'),
            'subopt_heading' => $locale->maketext('[asis,TailWatch] Drivers:'),
            'note'           => $locale->maketext('Disabling all drivers will effectively disable [asis,tailwatchd].'),
            'description'    => $locale->maketext('[asis,TailWatch] Daemon (Configurable Log Monitoring Service)'),
        },
    };

    return $SERVS;
}

sub _get_locale {
    require Cpanel::Locale;
    return Cpanel::Locale->get_handle();
}

sub _get_cpconf {
    require Cpanel::Config::LoadCpConf;
    return Cpanel::Config::LoadCpConf::loadcpconf_not_copy();
}

sub _is_cpdavd_needed {
    require Cpanel::LoadModule;

    # Avoid require() in order to hide from perlpkg:
    my $load_ok = eval { Cpanel::LoadModule::load_perl_module('Cpanel::ServiceConfig::cpdavd'); };
    return 0 unless $load_ok;
    return Cpanel::ServiceConfig::cpdavd::is_needed() ? 0 : 1;
}

sub _get_services {
    require Cpanel::PHPFPM::Controller;

    my $locale     = _get_locale();
    my $cpconf_ref = _get_cpconf();

    if ( !defined $SERVS ) {
        $SERVS = get_default_service_list( $locale, $cpconf_ref );

        # For PHP-FPM with Apache, we only want it to show and be monitored if at least one version is installed (via Easyapache 4)
        my $phpfpmversions_installed_ar = Cpanel::PHPFPM::Controller::get_phpfpm_versions();
        my $is_php_fpm_available        = @{$phpfpmversions_installed_ar};
        my $apache_php_fpm_description  = $locale->maketext('The PHP-FPM daemons for the [asis,Apache] Web Server are installed and removed using [asis,EasyApache 4] and may not be enabled or disabled here.');
        if ($is_php_fpm_available) {
            $SERVS->{'apache_php_fpm'} = {
                'name'           => $locale->maketext('[asis,PHP-FPM] service for [asis,Apache]'),
                'description'    => $apache_php_fpm_description,
                'skip_dnsonly'   => 1,
                'hide_from_ui'   => 1,
                'always_enabled' => 1,
            };
        }
        else {
            $SERVS->{'apache_php_fpm'} = {
                'name'               => $locale->maketext('[asis,PHP-FPM] service for [asis,Apache]'),
                'description'        => $apache_php_fpm_description,
                'skip_dnsonly'       => 1,
                'hide_from_ui'       => 1,
                'always_disabled'    => 1,
                'always_unmonitored' => 1,
            };
        }

        # Set named to always disabled and always unmonitored if the current nameserver is disabled.
        # This will prevent users from trying to enable the service when there is no running nameserver.
        if ( $cpconf_ref->{local_nameserver_type} && $cpconf_ref->{local_nameserver_type} eq 'disabled' ) {
            $SERVS->{named}{always_disabled}    = 1;
            $SERVS->{named}{always_unmonitored} = 1;
        }

    }

    # Any plugins are registered with chkservd
    # This makes 'cpanel-dovecot-solr' available
    my $drivers_ref = Cpanel::Chkservd::Config::Drivers::load_driver_directory($Cpanel::Chkservd::Config::chkservd_dir);
    foreach my $srv ( keys %$drivers_ref ) {
        next if $srv eq 'cpanalyticsd';         # Cruft from the defunct cpanalyticsd service might still be in the driver directory
        next if ref $SERVS->{$srv} eq 'HASH';

        my ( $name, $description );

        # Check if a custom name and description are set
        my @cfg_line = split( /,/, ( $drivers_ref->{$srv} // '' ) );
        my $module   = $cfg_line[8];
        if ($module) {
            local $@;
            require Cpanel::LoadModule::Custom;
            my $desc_hr = eval {
                Cpanel::LoadModule::Custom::load_perl_module($module);
                my $cr = $module->can("get_service_description_hashref");
                $cr ? $cr->() : undef;
            };
            Cpanel::Debug::log_error($@) if !$desc_hr && $@;

            # Intentionally not guarding against desc_hr not being hash here
            # per review commentary
            ( $name, $description ) = ( $desc_hr->{name}, $desc_hr->{description} );
        }

        $SERVS->{$srv} ||= { 'name' => $name || $srv, 'description' => $description || $srv };
    }

    # Filter out $SERVS based on required_role
    require Cpanel::Server::Type::Profile::Roles;

    foreach my $service ( keys %$SERVS ) {
        next unless ref $SERVS->{$service} eq 'HASH';
        next unless $SERVS->{$service}->{required_role};

        foreach my $role ( @{ $SERVS->{$service}->{required_roles} } ) {
            if ( !Cpanel::Server::Type::Profile::Roles::is_role_enabled($role) ) {
                delete $SERVS->{$service};
                last;
            }
        }
    }

    return $SERVS;
}

1;
