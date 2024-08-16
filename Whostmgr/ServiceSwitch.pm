package Whostmgr::ServiceSwitch;

# cpanel - Whostmgr/ServiceSwitch.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Cpanel::Config::LoadCpConf ();
use Cpanel::Services::Enabled  ();

sub getcfg {
    my $service = shift;

    return
        $service eq 'nameserver' ? _getcfg_nameserver()
      : $service eq 'mailserver' ? _getcfg_mailserver()
      : $service eq 'ftpserver'  ? _getcfg_ftpserver()
      :                            undef;
}

sub _getcfg_nameserver {
    require Cpanel::NameServer::Utils::Enabled;
    my $cpconf_ref = Cpanel::Config::LoadCpConf::loadcpconf();
    my %warnings;
    my %available = ( 'BIND' => 1, 'PowerDNS' => 1, 'DISABLED' => 1 );

    my $current = defined $cpconf_ref->{'local_nameserver_type'} ? uc( $cpconf_ref->{'local_nameserver_type'} ) : 'BIND';

    my $num_zones = 0;

    eval {
        require Cpanel::NameServer::Conf;
        my $conf_obj = Cpanel::NameServer::Conf->new() || die;
        my $zone_ref = $conf_obj->fetchzones();
        $num_zones = scalar @{$zone_ref};
    };

    foreach my $ns ( keys %available ) {
        ( $available{$ns}, $warnings{$ns} ) = Cpanel::NameServer::Utils::Enabled::valid_nameserver_type($ns);
    }

    if ( $available{'NSD'} && $num_zones > 500 ) {
        $warnings{'NSD'} = "Performance will suffer because ${num_zones} zones are in use.";
    }

    return ( $current, \%available, \%warnings );
}

sub _getcfg_ftpserver {
    my $cpconf_ref = Cpanel::Config::LoadCpConf::loadcpconf();
    my %available  = ( 'ProFTPD' => 1, 'Pure-FTPd' => 1, 'Disabled' => 1 );
    my $current    = defined $cpconf_ref->{'ftpserver'} ? ( grep { lc($_) eq $cpconf_ref->{'ftpserver'} } keys %available )[0] : 'Pure-FTPd';
    $current = 'Disabled' if Cpanel::Services::Enabled::is_enabled('ftp') == 0;
    return ( $current, \%available, {} );
}

sub _getcfg_mailserver {
    my $cpconf_ref = Cpanel::Config::LoadCpConf::loadcpconf();
    my %available  = ( 'DOVECOT' => 1, 'DISABLED' => 1 );
    my $current    = uc( $cpconf_ref->{'mailserver'} );
    $current = 'DISABLED' if Cpanel::Services::Enabled::is_enabled('mail') == 0;
    return ( $current, \%available, {} );
}

1;
