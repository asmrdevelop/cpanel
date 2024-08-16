package Cpanel::ApacheConf::Parser;

# cpanel - Cpanel/ApacheConf/Parser.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Tie::IxHash                       ();
use Cpanel::ApacheConf::Parser::Regex ();
use Cpanel::Config::Httpd::IpPort     ();
use Cpanel::Hostname                  ();
use Cpanel::IP::Parse                 ();
use Cpanel::Debug                     ();
use Cpanel::WildcardDomain            ();

our $VERSION = '3.8';

sub vhost_record_parser {
    my ($httpdconf_text_ref) = @_;

    my %RECORDS;
    tie %RECORDS, 'Tie::IxHash';

    if ( !ref $httpdconf_text_ref ) {
        my $httpdconf_text_ref_copy = $httpdconf_text_ref;
        $httpdconf_text_ref = \$httpdconf_text_ref_copy;
    }

    my $records_aliasmap_ref       = {};
    my $records_vhosts_offsets_ref = {};
    my $records_ipmap_ref          = {};

    $RECORDS{'__aliasmap__'}       = $records_aliasmap_ref;
    $RECORDS{'__vhosts_offsets__'} = $records_vhosts_offsets_ref;
    $RECORDS{'__ipmap__'}          = $records_ipmap_ref;

    return \%RECORDS if !$$httpdconf_text_ref;

    if ( substr( $$httpdconf_text_ref, 0, 1 ) eq '<' ) {    # handle being passed a single vhost
        $$httpdconf_text_ref = "\n" . $$httpdconf_text_ref;
    }

    my (
        $vhost_start_pos, $vhost_ips, $vhost_contents, $ip, $port, $servername,
        %aliases
    );

    if ( $$httpdconf_text_ref =~ m/\n[ \t]*Include[ \t]+.*?post_virtualhost_/ ) {
        $RECORDS{'__post_virtualhost_include_offset__'} = int $-[0];
    }

    my %seen_ip_port_servername;
    my $default_host_port;
    my $serveralias_capture_regex = Cpanel::ApacheConf::Parser::Regex::VirtualHost_ServerAlias_Capture();
    my $servername_capture_regex  = Cpanel::ApacheConf::Parser::Regex::VirtualHost_ServerName_Capture();
    my $server_hostname;

    #NOTE: Check perldoc perlvar for what @- does.
    while ( $$httpdconf_text_ref =~ m/(\n[ \t]*# CPANEL\/WHM\/WEBMAIL.*?PROXY SUBDOMAINS)?[\s\n]*(\n\<virtualhost[ \t]+([^\>]+)\>)(.*?)(?:<\/virtualhost\>)/sig ) {
        if ($1) {
            my $cur_offset = int $-[1];
            if ( !defined $RECORDS{'__proxy_start__'} || ( $cur_offset < $RECORDS{'__proxy_start__'} ) ) {
                $RECORDS{'__proxy_start__'} = $cur_offset;
            }

            next;
        }

        #NOTE: We checked for $1 (service (formerly proxy) subdomains comment) above.
        #Also, note that $vhost_start_pos is the start of the beginning \n.
        ( $vhost_start_pos, $vhost_ips, $vhost_contents ) = ( int( $-[2] ), $3, $4 );

        if ( $vhost_contents =~ m{$servername_capture_regex}o ) {

            # wildcard encoded domain names must be decoded for Cpanel::ApacheConf::loadhttpdconf
            $servername = Cpanel::WildcardDomain::decode_wildcard_domain( lc $1 );
            my $servername_record_ref = ( $RECORDS{$servername} ||= {} );
            %aliases = ();
            while ( $vhost_contents =~ m/$serveralias_capture_regex/og ) {
                @aliases{ split( m/[ \t]+/, lc $1 ) } = ();
            }
            delete $aliases{$servername};    # The servername may be in the
                                             # alias list due to Apache 2.4's handling
                                             # of wildcard domains
            if ( scalar keys %aliases ) {
                @{ $servername_record_ref->{'aliases'} } = sort keys %aliases;
                @{$records_aliasmap_ref}{ keys %aliases } = ($servername) x scalar keys %aliases;
            }

            foreach my $vip ( split( m/[ \t]+/, $vhost_ips ) ) {
                my ( $version, $ip, $port ) = Cpanel::IP::Parse::parse( $vip, undef, $Cpanel::IP::Parse::BRACKET_IPV6 );
                $port ||= ( $default_host_port ||= Cpanel::Config::Httpd::IpPort::get_main_httpd_port() );

                if ( $seen_ip_port_servername{"${ip}_${port}_${servername}"}++ ) {
                    Cpanel::Debug::log_warn("Duplicate servername/ip/port combination found in Apache configuration: $servername/$ip/$port. Ignoring for Apache configuration datastore.");
                    next;
                }

                my $vhost_offset_key = get_vhost_offset_key( $servername, $port );
                if ( exists $records_vhosts_offsets_ref->{$vhost_offset_key}
                    and $records_vhosts_offsets_ref->{$vhost_offset_key} ne $vhost_start_pos ) {
                    if ( $servername ne ( $server_hostname ||= Cpanel::Hostname::gethostname() ) ) {
                        Cpanel::Debug::log_warn("Duplicate servername/port combination found in Apache configuration: $servername/$port. Ignoring for Apache configuration datastore.");
                    }
                    next;
                }

                $records_vhosts_offsets_ref->{$vhost_offset_key} = $vhost_start_pos;

                push @{ $records_ipmap_ref->{$ip}{$port} }, $servername;
                push(
                    @{ $servername_record_ref->{'address'} },
                    {
                        'ip'   => $ip,
                        'port' => $port,
                    }
                );
            }

            if ( $vhost_contents =~ m/\n[ \t]*documentroot[ \t]+(\S+)/is ) {
                $servername_record_ref->{'docroot'} = $1;
            }
            if ( $vhost_contents =~ m/\n[ \t]*##[ \t]+User[ \t]+(\S+)[ \t]+#[ \t]+Needed[ \t]+/is ) {
                $servername_record_ref->{'user'} = $1;
            }
            elsif ( $vhost_contents =~ m/\n[ \t]*(?:SuexecUserGroup|User)[ \t]+(\S+)/is ) {
                $servername_record_ref->{'user'} = $1;
            }
            $servername_record_ref->{'cgi'} = ( $vhost_contents =~ m/\n[ \t]*options.*?-execcgi/is ) ? 0 : 1;
        }
    }

    return \%RECORDS;
}

sub get_vhost_offset_key {
    return $_[0] . ' ' . $_[1];

    #my ( $servername, $port ) = @_;
    #return "$servername $port";
}

1;
