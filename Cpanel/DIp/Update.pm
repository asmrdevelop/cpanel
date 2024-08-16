package Cpanel::DIp::Update;

# cpanel - Cpanel/DIp/Update.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::Config::userdata::Cache ();
use Cpanel::ConfigFiles             ();
use Cpanel::Hostname                ();
use Cpanel::FileUtils::Write        ();
use Cpanel::Config::LoadWwwAcctConf ();
use Cpanel::IP::Parse               ();
use Cpanel::LoadModule              ();
use Cpanel::Exception               ();

use Try::Tiny;

sub update_dedicated_ips_and_dependencies_or_die {
    my ( $ok, $msg ) = update_dedicated_ips();
    die $msg if !$ok;

    Cpanel::LoadModule::load_perl_module('Cpanel::FtpUtils::PureFTPd');
    ( $ok, $msg ) = 'Cpanel::FtpUtils::PureFTPd'->can('build_pureftpd_roots')->();
    die $msg if !$ok;

    return $ok;
}

# update_dedicated_ips_and_dependencies_or_warn returns
# undef on success or the error as a string
sub update_dedicated_ips_and_dependencies_or_warn {
    my $err;
    try {
        update_dedicated_ips_and_dependencies_or_die();
    }
    catch {
        $err = $_;
    };

    if ($err) {
        my $err_as_string = Cpanel::Exception::get_string($err);
        _logger()->warn($err_as_string);
        return $err_as_string;
    }

    # Return undef if no error
    return undef;
}

sub update_dedicated_ips {

    #   Get the main shared IP address
    my $conf    = Cpanel::Config::LoadWwwAcctConf::loadwwwacctconf();
    my $main_ip = $conf->{'ADDR'} // '';

    #   Compile a list of IPs that have been assigned to resellers;
    #   these are to be excluded from /etc/domainips, as they are by definition not dedicated to a single site
    my %reseller_ips;
    if ( opendir my $rip_files, $Cpanel::ConfigFiles::MAIN_IPS_DIR ) {
        my @rip_files = grep { !/^\./ } ( readdir $rip_files );
        closedir $rip_files;
        for my $rip_file ( map { "$Cpanel::ConfigFiles::MAIN_IPS_DIR/$_" } @rip_files ) {
            if ( open my $fh, '<', $rip_file ) {
                @reseller_ips{ grep { !/^\s+$/ } map { chomp; $_ } <$fh> } = ();
                close $fh;
            }
        }
    }

    my %seen_ip;

    my $FIELD_USER        = $Cpanel::Config::userdata::Cache::FIELD_USER;
    my $FIELD_DOMAIN_TYPE = $Cpanel::Config::userdata::Cache::FIELD_DOMAIN_TYPE;

    my %user_to_primary_domain_map_ref;

    {
        my $userdata = Cpanel::Config::userdata::Cache::load_cache();
        my ( $user, $domain_type, $ip, $ip_and_port );    # outside of loop since the loop can be 50k+
        my %MEMORIZED_IP_PARSE;

        for my $dns_name ( keys %{$userdata} ) {

            ( $user, $domain_type, $ip_and_port ) = @{ $userdata->{$dns_name} }[ $FIELD_USER, $FIELD_DOMAIN_TYPE, 5 ];

            next if $domain_type ne 'main';

            $user_to_primary_domain_map_ref{$user} = $dns_name;

            $ip = ( $MEMORIZED_IP_PARSE{$ip_and_port} ||= ( Cpanel::IP::Parse::parse($ip_and_port) )[1] );    #Strip port number

            next if ( $ip eq $main_ip || exists $reseller_ips{$ip} );

            $seen_ip{$ip}{$user} = 1;
        }
    }

    my $hostname;
    my %DOMAINIPS;
    for my $ip ( keys %seen_ip ) {

        # More then one user has the ip
        next if ( scalar keys %{ $seen_ip{$ip} } > 1 );

        # We need the user to get their main domain, its the first key
        my $ip_user = ( keys %{ $seen_ip{$ip} } )[0];

        # The domainips file should show the primary domain for the user
        $DOMAINIPS{$ip} = $user_to_primary_domain_map_ref{$ip_user} || ( $hostname ||= Cpanel::Hostname::gethostname() );
    }

    Cpanel::FileUtils::Write::overwrite( $Cpanel::ConfigFiles::DEDICATED_IPS_FILE, "#domainips v1\n" . join( "\n", map { "$_: $DOMAINIPS{$_}" } sort keys %DOMAINIPS ) . "\n", 0644 );

    if ( $INC{'Cpanel/DIp/IsDedicated.pm'} ) {
        Cpanel::DIp::IsDedicated::clearcache();
    }

    return ( 1, \%DOMAINIPS );
}

{
    my $_logger;

    sub _logger {
        return $_logger //= do {
            require Cpanel::Logger;
            Cpanel::Logger->new();
        };
    }
}

1;
