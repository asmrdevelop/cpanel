package Cpanel::Services::Installed::State;

# cpanel - Cpanel/Services/Installed/State.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::Config::LoadCpConf  ();
use Cpanel::Chkservd::Manage    ();
use Cpanel::Server::Type        ();
use Cpanel::Services::List      ();
use Cpanel::Services::Group     ();
use Cpanel::Services::Enabled   ();
use Cpanel::Services::Installed ();
use Cpanel::LoadModule          ();

our $CHKSRVD_DIR = '/etc/chkserv.d';

sub get_installed_services_state {
    my $services             = {};
    my $extra_services       = {};
    my $monitored_status_for = _get_service_monitored_status();
    my $cpconf_ref           = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();

    my $all_service_names               = _get_handled_services();
    my $always_enabled_services_ref     = $all_service_names->{'always_enabled_services'};
    my $always_disabled_services_ref    = $all_service_names->{'always_disabled_services'};
    my $always_unmonitored_services_ref = $all_service_names->{'always_unmonitored_services'};

    my @service_list;
    foreach my $type ( 'services', 'extra_services' ) {
        foreach my $name ( @{ $all_service_names->{$type} } ) {
            my $chkservd_name = $name;

            require Cpanel::Server::Type::Profile::Roles;
            next if !Cpanel::Server::Type::Profile::Roles::is_service_allowed($name);

            if ( $name eq 'pop' && $type eq 'extra_services' ) {

                # Case 109357
                # Temporary measure to remove "pop" from the Service Manager under
                # Additional Services.  A future feature team should fix this in the
                # general case and remove this code.
                next;
            }

            my $altname = qq{};

            if ( $name eq 'imap' || $name eq 'pop' || $name eq 'lmtp' ) {
                if ( 'disabled' eq $cpconf_ref->{'mailserver'} && $name ne 'lmtp' ) {

                    # If 'mailserver' is explicitly configured to be 'disabled' then
                    # there won't be a imap/pop service installed on the server to enable/monitor.
                    next;
                }
            }
            elsif ( 'named' eq $name
                && defined $cpconf_ref->{'local_nameserver_type'} ) {
                if ( grep { $_ eq $cpconf_ref->{'local_nameserver_type'} } qw{powerdns disabled} ) {
                    $altname = $cpconf_ref->{'local_nameserver_type'};
                }
            }

            if ( $name eq 'exim-altport' ) {
                opendir( my $dh, '/etc/chkserv.d' );
                my @entries = readdir($dh);
                closedir($dh);
                @entries = grep( !m{-cpanelsync$}, @entries );    # CPANEL-5659: light defense for -cpanelsync files until this can be refactored
                @entries = grep( !m{\.rpm[^\.]+$}, @entries );    # CPANEL-5659: light defense for .rpmorig, .rpmsave files until this can be refactored
                my ($entry) = grep { /^exim-([,0-9]+)/ } @entries;
                $chkservd_name = $entry if defined $entry;
            }

            # this is weird... meaning is reversed here.... [ preserving original behavior ]
            #   view servicemanager.tmpl
            my $disabled_flag = Cpanel::Services::Enabled::is_enabled($name) ? 1 : 0;

            my $suboptions = get_service_suboptions($name);

            my $canon = Cpanel::Services::List::canonicalize_service( $name, $disabled_flag, $monitored_status_for );

            # disabled value is altered for exim
            ( $chkservd_name, $disabled_flag, $monitored_status_for->{$name}, my $setting ) = @{$canon}{qw/service enabled monitored settings/};
            my $group = Cpanel::Services::Group::get_service_group($name);

            push @service_list,
              {
                'name'               => $name,
                'chkservd_name'      => $chkservd_name,
                'type'               => $type,
                'monitored'          => $monitored_status_for->{$name},
                'enabled'            => $disabled_flag,
                'always_enabled'     => ( $always_enabled_services_ref->{$name}     ? 1 : 0 ),
                'always_disabled'    => ( $always_disabled_services_ref->{$name}    ? 1 : 0 ),
                'always_unmonitored' => ( $always_unmonitored_services_ref->{$name} ? 1 : 0 ),
                'suboptions'         => $suboptions,
                'setting'            => $setting,
                'altname'            => $altname,
                'group'              => $group,
                'display_name'       => $all_service_names->{services_details}{$name}{name},
                'subopt_heading'     => $all_service_names->{services_details}{$name}{subopt_heading},
                'note'               => $all_service_names->{services_details}{$name}{note},
                ( map { $_ => $all_service_names->{services_details}{$name}{$_} } grep { m/^description/ } keys %{ $all_service_names->{services_details}{$name} } )
              };
        }

    }

    return \@service_list;
}

sub get_service_suboptions {
    my $service_name = shift;

    if ( 'tailwatchd' eq $service_name ) {
        my $module = "Cpanel::TailWatch";
        Cpanel::LoadModule::load_perl_module($module);
        no warnings 'once';
        my $suboptions = "$module"->new( { 'type' => $Cpanel::TailWatch::TAILWATCH_OBJECT_TINY, 'param_obj' => '' } )->get_driver_hashref();
        if ( keys %$suboptions ) {
            return $suboptions;
        }
    }

    return;
}

sub _get_service_monitored_status {
    my $monitored = Cpanel::Chkservd::Manage::getmonitored();
    $monitored->{'tailwatchd'} = -1;
    return $monitored;
}

*get_handled_services = *_get_handled_services;

sub _get_handled_services {
    my %handled_services;
    my @extra_services;
    my %always_enabled_services;
    my %always_disabled_services;
    my %always_unmonitored_services;
    my $cpservices = Cpanel::Services::List::get_service_list();

    $handled_services{'cpsrvd'} = 0;    # cpsrvd alway monitored

    my $SRVS = _get_chksrvd_srvs();

    my @uniq_services = keys { map { $_ => 1 } keys %{$cpservices}, @$SRVS }->%*;

    foreach my $service (@uniq_services) {
        next if $service =~ m/^\.+$/;
        next if $service eq 'chkservd.conf';
        next if ( $service =~ m/^exim\-/ );
        next if ( $service =~ m/-cpanelsync/ );
        next if ( $service =~ m{\.rpm[^\.]+$} );    # CPANEL-5659: light defense for .rpmorig, .rpmsave files until this can be refactored
        next if ( $service eq 'antirelayd' || $service eq 'chkservd' || $service eq 'eximstats' || $service eq 'queueprocd' || $service eq 'cpanellogd' );
        next if ( $service =~ m/^clamd\.(?:rpmorig|rpmsave)$/ );
        next if ( $service eq 'cpanalyticsd' );
        next if Cpanel::Server::Type::is_dnsonly() && $cpservices->{$service} && $cpservices->{$service}{'skip_dnsonly'};

        # looking for non cpanel services
        if ( !exists $cpservices->{$service} ) {
            push @extra_services, $service;
        }
        elsif ( !exists $handled_services{$service} && Cpanel::Services::Installed::service_is_installed($service) ) {
            $handled_services{$service} = 1;
        }
        if ( $cpservices->{$service} && $cpservices->{$service}{'always_enabled'} ) {
            $always_enabled_services{$service} = 1;
        }
        if ( $cpservices->{$service} && $cpservices->{$service}{'always_disabled'} ) {
            $always_disabled_services{$service} = 1;
        }
        if ( $cpservices->{$service} && $cpservices->{$service}{'always_unmonitored'} ) {
            $always_unmonitored_services{$service} = 1;
        }
    }

    if ( exists $handled_services{'exim'} ) {
        $handled_services{'exim-altport'} = 1;
    }

    my @services = grep { $handled_services{$_} } keys %handled_services;

    my $all_services = {
        'services'                    => \@services,
        'extra_services'              => \@extra_services,
        'always_enabled_services'     => \%always_enabled_services,
        'always_disabled_services'    => \%always_disabled_services,
        'always_unmonitored_services' => \%always_unmonitored_services,
        'services_details'            => $cpservices,
    };
    return $all_services;
}

sub _get_chksrvd_srvs {

    my @SRVS;
    if ( opendir my $chksrvd_dh, $CHKSRVD_DIR ) {
        @SRVS = readdir $chksrvd_dh;
        closedir $chksrvd_dh;
    }

    return \@SRVS;
}

1;
