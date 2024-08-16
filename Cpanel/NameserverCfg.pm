package Cpanel::NameserverCfg;

# cpanel - Cpanel/NameserverCfg.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;
use Cpanel::ConfigFiles             ();
use Cpanel::Config::LoadWwwAcctConf ();
use Cpanel::Exception               ();
use Cpanel::LoadFile                ();

our $MAX_NAMESERVER_COUNT = 4;

sub fetch {
    my ($reseller) = @_;

    my $ns_ref;

    if ( $reseller && $reseller ne 'root' ) {
        $ns_ref = fetch_reseller_nameservers($reseller);
    }

    if ( !$ns_ref || !@{$ns_ref} ) {
        $ns_ref = fetch_root_nameservers();
    }

    return $ns_ref ? @{$ns_ref} : ();
}

my $_fetch_root_nameservers;

sub clear_cache {
    undef $_fetch_root_nameservers;
    return;
}

sub generate_default_nameservers {
    require Cpanel::Domain::ExternalResolver;    # t/02_binary_ldd_check.t complains if this is compiled in to whostmgr binaries
    require Cpanel::Hostname;

    my $hostname = Cpanel::Hostname::gethostname();

    if ( !$hostname || $hostname !~ /[.]/ ) {
        return '', '';
    }

    my @hostnameparts  = split /[.]/, $hostname;
    my $hostnamedomain = join '.', @hostnameparts[ 1 .. $#hostnameparts ];

  SUFFIX:
    for my $method (
        [ $hostnamedomain, sub { Cpanel::Domain::ExternalResolver::domain_resolves(shift) } ],
        [ $hostname,       sub { Cpanel::Domain::ExternalResolver::domain_is_on_local_server(shift) } ],
    ) {
        my ( $suffix, $validation ) = @$method;

        my ( $ns, $ns2 ) = map { $_ . $suffix } qw(ns1. ns2.);
        for ( $ns, $ns2 ) {
            if ( eval { $validation->($_) } ) {
                return $ns, $ns2;    # Only require one to be valid
            }
            elsif ( my $exception = $@ ) {    # Treat all DNS errors the same as a nonexistent domain
                print STDERR Cpanel::Exception::get_string_no_id($exception) . "\n";
            }
        }
    }

    my $last_choice_suffix = @hostnameparts > 2 ? $hostnamedomain : $hostname;
    return map { $_ . $last_choice_suffix } qw(ns1. ns2.);
}

sub fetch_root_nameservers {
    return $_fetch_root_nameservers if $_fetch_root_nameservers;
    my $wwwacctconf_ref = Cpanel::Config::LoadWwwAcctConf::loadwwwacctconf();
    return if !$wwwacctconf_ref;

    my @nameservers;

    # Should this go to $MAX_NAMESERVER_COUNT? Not many places in the code allow for up to 10 nameservers
    foreach my $idx ( '', 2 .. 10 ) {
        if ( exists $wwwacctconf_ref->{ 'NS' . $idx } && $wwwacctconf_ref->{ 'NS' . $idx } ) {
            push @nameservers, $wwwacctconf_ref->{ 'NS' . $idx };
        }
    }

    return ( $_fetch_root_nameservers = \@nameservers );
}

sub fetch_reseller_nameservers {
    my ($reseller) = @_;
    return if !$reseller;

    my @nameservers;

    my $data = Cpanel::LoadFile::load_if_exists($Cpanel::ConfigFiles::RESELLERS_NAMESERVERS_FILE);
    if ( length $data ) {
        foreach my $line ( split( m/\n/, $data ) ) {
            if ( index( $line, "$reseller:" ) == 0 ) {
                my $nameserver_list = ( split( m{:[ \t]*}, $line ) )[1];
                if ( length $nameserver_list ) {
                    foreach my $name_srv ( split( /\,/, $nameserver_list ) ) {
                        next if !$name_srv;
                        push @nameservers, $name_srv;
                    }
                }
            }
        }
    }

    return \@nameservers;
}

sub get_all_reseller_nameservers {
    my %res;
    my $data = Cpanel::LoadFile::load_if_exists($Cpanel::ConfigFiles::RESELLERS_NAMESERVERS_FILE);
    if ( length $data ) {
        foreach my $line ( split( m/\n/, $data ) ) {
            my ( $reseller, $nameserver_list ) = ( split( m{:[ \t]*}, $line ) )[ 0, 1 ];
            if ( length $nameserver_list ) {
                $res{$reseller} = [ grep { length } split( /\,/, $nameserver_list ) ];
            }
        }
    }
    return \%res;
}

#ensure that the number of elements equals the number of nameserver fields
sub fetch_full_reseller_nameservers {
    my $ns_ref = fetch_reseller_nameservers(@_);
    return if !$ns_ref;

    # should this put in q{} instead of undef?
    return [ map { $ns_ref->[$_] || undef } ( 0 .. $MAX_NAMESERVER_COUNT - 1 ) ];
}

sub fetch_ttl_conf {
    my ($wwwacctconf_ref) = @_;

    $wwwacctconf_ref ||= Cpanel::Config::LoadWwwAcctConf::loadwwwacctconf();

    my $ttl   = $wwwacctconf_ref->{'TTL'};
    my $nsttl = $wwwacctconf_ref->{'NSTTL'};

    # Ensure nameserver ttl and zone ttl are set properly
    if ( !$ttl || $ttl !~ m{ \A \d+ \z }xms ) {
        $ttl = '14400';
    }
    if ( !$nsttl || $nsttl !~ m{ \A \d+ \z }xms ) {
        $nsttl = '86400';
    }

    return ( $ttl, $nsttl );
}

1;
