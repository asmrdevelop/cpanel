package Whostmgr::API::1::Httpd;

# cpanel - Whostmgr/API/1/Httpd.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::AcctUtils::DomainOwner::Tiny ();
use Cpanel::AcctUtils::Owner             ();
use Cpanel::DIp::Owner                   ();
use Cpanel::DIp::MainIP                  ();
use Cpanel::HttpUtils::ApRestart::BgSafe ();
use Cpanel::DomainIp                     ();
use Whostmgr::ACLS                       ();
use Whostmgr::Resellers::Ips             ();

use constant NEEDS_ROLE => 'WebServer';

my $DEBUG = 0;

sub _die {
    my ($msg) = @_;

    die $msg . ( $DEBUG ? q{} : "\n" );
}

sub set_primary_servername {
    my ( $args, $metadata ) = @_;

    require Cpanel::Locale;
    local $@;
    my $httpd_conf_obj;
    eval {
        my $servername = $args->{'servername'};
        if ( !length $servername ) {
            my $locale = Cpanel::Locale->get_handle();
            _die( $locale->maketext( 'The “[_1]” parameter is missing.', 'servername' ) );
        }

        my $type = $args->{'type'};
        if ( !length $type ) {
            $type = 'std';
        }
        elsif ( $type ne 'ssl' && $type ne 'std' ) {
            my $locale = Cpanel::Locale->get_handle();
            _die( $locale->maketext( 'The “[_1]” parameter, if given, must be one of these values: [join, ,_2]', 'type', [ 'std', 'ssl' ] ) );
        }

        #If the operating user doesn't have root access, then we authorize
        #for both the domain and the IP.
        #
        #Domain must be owned by the reseller or one of the reseller's users.
        #IP must be one of:
        #   - an IP dedicated to one of the reseller's users
        #   - the reseller's dedicated IP
        #   - the reseller's shared IP (but NOT the server's main IP!)
        if ( !Whostmgr::ACLS::hasroot() ) {
            my $domainowner = Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner( $servername, { default => q{} } );
            if ( !$domainowner || !_i_can_control_account($domainowner) ) {
                my $locale = Cpanel::Locale->get_handle();
                _die( $locale->maketext( 'You do not control a domain called “[_1]”.', $servername ) );
            }

            my $ip = Cpanel::DomainIp::getdomainip($servername);
            if ( !$ip ) {
                my $locale = Cpanel::Locale->get_handle();
                _die( $locale->maketext( 'The system failed to determine the IP address for “[_1]” because of an unknown error.', $servername ) );
            }

            #Check shared IP access.
            if ( !Cpanel::DIp::Owner::get_dedicated_ip_owner($ip) ) {
                my $shared_ip = Whostmgr::Resellers::Ips::get_reseller_mainip( $ENV{'REMOTE_USER'} );
                if ( !$shared_ip ) {
                    my $locale = Cpanel::Locale->get_handle();
                    _die( $locale->maketext( '“[_1]” is not hosted on a dedicated IP address, and the system failed to determine your shared IP address.', $servername ) );
                }

                if ( $ip ne $shared_ip ) {
                    my $locale = Cpanel::Locale->get_handle();
                    _die( $locale->maketext( '“[_1]” is hosted on an IP address ([_2]) that you do not control.', $ip ) );
                }

                if ( $shared_ip eq Cpanel::DIp::MainIP::getmainip() ) {
                    my $locale = Cpanel::Locale->get_handle();
                    _die( $locale->maketext( '“[_1]” is hosted on the server’s main IP address ([_2]). Only root can set a primary website on the server’s main IP address.', $servername, $ip ) );
                }
            }
        }

        require Cpanel::HttpUtils::Config::Apache;
        $httpd_conf_obj = Cpanel::HttpUtils::Config::Apache->new();

        # we can die here, and the config object need to be closed manually ( due to a circular reference )
        my ( $ok, $msg ) = $httpd_conf_obj->set_primary_servername( $servername, $type );
        ( $ok, $msg ) = $httpd_conf_obj->save() if $ok;

        if ( !$ok ) {
            $httpd_conf_obj->close();
            _die($msg);
        }
        Cpanel::HttpUtils::ApRestart::BgSafe::restart();
    };

    if ( defined $httpd_conf_obj ) {
        $httpd_conf_obj->close();
    }

    chomp $@;

    @{$metadata}{qw(result reason)} = $@ ? ( 0, $@ ) : qw(1 OK);
    return;
}

sub _i_can_control_account {
    my ($account) = @_;

    return 1 if $account eq $ENV{'REMOTE_USER'};

    return 1 if $ENV{'REMOTE_USER'} eq Cpanel::AcctUtils::Owner::getowner($account);

    return 0;
}

1;
