package Cpanel::SPF;

# cpanel - Cpanel/SPF.pm                             Copyright 2022 cPanel L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Config::LoadCpUserFile ();
use Cpanel::Config::HasCpUserFile  ();
use Cpanel::DnsUtils::Install      ();
use Cpanel::DnsUtils::AskDnsAdmin  ();
use Cpanel::DIp::MainIP            ();
use Cpanel::Debug                  ();
use Cpanel::DIp::Mail              ();
use Cpanel::LoadModule             ();
use Cpanel::NAT                    ();
use Cpanel::Validate::IP::v4       ();
use Cpanel::SPF::String            ();

sub remove_spf {
    my %OPTS = @_;
    return setup_spf( 'user' => $OPTS{'user'}, 'delete' => 1 );
}

sub remove_a_domains_spf {
    my %OPTS = @_;
    return setup_spf( 'domain' => $OPTS{'domain'}, 'delete' => 1 );
}

sub has_spf {
    my %OPTS = @_;

    my $user = $OPTS{'user'};
    return 0 unless ( $user && Cpanel::Config::HasCpUserFile::has_cpuser_file($user) );
    my $cpuser_ref = Cpanel::Config::LoadCpUserFile::loadcpuserfile($user);

    if ( !UNIVERSAL::isa( $cpuser_ref, 'HASH' ) ) {
        return 0;
    }

    return $cpuser_ref->{'HASSPF'} ? 1 : 0;
}

#Enforces default: +a +mx +ip4:<server IP> ~all
sub make_spf_string {    ## no critic qw(Subroutines::ProhibitExcessComplexity) -- see TODO
    my ( $mechanisms_ar, $mods_hr, $is_complete, $domain ) = @_;

    my $mainip = Cpanel::NAT::get_public_ip( Cpanel::DIp::MainIP::getmainserverip() );
    my @dedicated_ips;

    # We have to accept an IP here for account creation.
    if ($domain) {
        if ( Cpanel::Validate::IP::v4::is_valid_ipv4($domain) ) {
            @dedicated_ips = ($domain);
        }
        else {
            my ( $mail_ips, $from_where ) = Cpanel::DIp::Mail::get_mail_ip_for_domain($domain);

            # strip ipv6 addresses when falling back to the default handler; accounts must be explicitly assigned an address #
            @dedicated_ips = grep { $from_where eq 'DEDICATED' or $from_where eq 'DEFAULT' } split( m/;\s*/, $mail_ips || '' );
        }
    }

    # create the initial construct of the string and add any dedicated IPs to the string #
    my $string = "v=spf1 +a +mx +ip4:$mainip";
    require Cpanel::SPF::Include;
    my $spf_include_hosts_ar = Cpanel::SPF::Include::get_spf_include_hosts();

    if (@dedicated_ips) {
        my $ded_str = join( ' ', map { m/:/ ? "+ip6:$_" : "+ip4:" . Cpanel::NAT::get_public_ip($_) } grep { $_ ne $mainip } @dedicated_ips );
        $string .= ' ' . $ded_str if $ded_str;
    }
    Cpanel::SPF::String::add_spf_includes( \$string, $spf_include_hosts_ar );

    if ( 'ARRAY' eq ref $mechanisms_ar ) {
        #
        # TODO refactor this into _add_existing_spf_mechanisms
        # to reduce complexity
        #
        for my $mechanism (@$mechanisms_ar) {
            my $spf_part;
            if ( my $ref = ref $mechanism ) {
                if ( $ref eq 'ARRAY' ) {
                    $spf_part = ( $mechanism->[0] || '+' ) . lc( $mechanism->[1] ) . ( length $mechanism->[2] ? ":$mechanism->[2]" : q{} );
                }
                else {
                    Cpanel::Debug::log_warn("Invalid SPF reference: $ref");
                    next;
                }
            }
            else {
                if ( $mechanism !~ m{\A.?all\z}i && $mechanism !~ tr{:}{} ) {
                    Cpanel::Debug::log_warn("Invalid SPF string: $mechanism");
                    next;
                }
                if ( $mechanism =~ s/:([+~?-])/:/ ) {
                    $mechanism = "$1$mechanism";
                }
                if ( $mechanism =~ m{\A[+~?-]} ) {
                    $spf_part = $mechanism;
                }
                else {
                    $spf_part = "+$mechanism";
                }
            }

            next if $spf_part =~ m{\A\+?a\z}i;
            next if $spf_part =~ m{\A\+?mx\z}i;
            next if $spf_part =~ m{\A\+?ip4:\Q$mainip\E\z}i;
            next if grep { $spf_part =~ m{\A\+?ip[46]:\Q$_\E\z}i } @dedicated_ips;
            next if grep { $spf_part =~ m{\A\+?include:\Q$_\E\z}i } @$spf_include_hosts_ar;

            $string .= " $spf_part";
        }
    }

    if ( 'HASH' eq ref $mods_hr ) {

        #sort so that we know what the string will look like and can test more easily
        for ( sort keys %$mods_hr ) {
            $string .= " $_=$mods_hr->{$_}";
        }
    }

    if ( $string !~ m{\s[+~?-]all\b} ) {
        $string .= $is_complete ? ' -all' : ' ~all';
    }

    return $string;
}

#
# This function will overwrite existing records by default
#
# If the user already has SPF you
# should probably Cpanel::SPF::Update::update_spf_records
# unless you are creating a new domain
#
sub setup_spf {
    my %OPTS        = @_;
    my $delete      = $OPTS{'delete'};
    my $keys        = $OPTS{'spf_keys'};
    my $is_complete = $OPTS{'is_complete'};
    my $zone_ref    = $OPTS{'zone_ref'};             # Allow passing in the hashref in the format Cpanel::DnsUtils::Fetch returns
    my $overwrite   = $OPTS{'overwrite'};
    my $skipreload  = $OPTS{'skipreload'} ? 1 : 0;
    my $parent      = $OPTS{'parent'};               # may be undef

    # XXX BAD BAD
    # Do not use this flag if you can help it. It doesn’t have good
    # test coverage. Use Cpanel::SPF::Update instead.
    my $preserve = $OPTS{'preserve'};    # case 60047 - preserve custom SPF records

    my $domains_ref;
    my $domain;
    if ( exists $OPTS{'domain'} ) {
        $domain      = $OPTS{'domain'};
        $domains_ref = [$domain];
    }
    elsif ( exists $OPTS{'user'} ) {
        my $user = $OPTS{'user'};
        unless ( Cpanel::Config::HasCpUserFile::has_cpuser_file($user) ) {
            Cpanel::LoadModule::load_perl_module('Cpanel::Locale') if !$INC{'Cpanel/Locale.pm'};

            return ( 0, Cpanel::Locale->get_handle()->maketext( 'Invalid user “[_1]”.', $user ) );
        }
        my $cpuser_ref = Cpanel::Config::LoadCpUserFile::loadcpuserfile($user);
        $domain = $cpuser_ref->{'DOMAIN'};

        $domains_ref = [ $cpuser_ref->{'DOMAIN'} ];
        if ( ref $cpuser_ref->{'DOMAINS'} eq 'ARRAY' ) {
            push @{$domains_ref}, @{ $cpuser_ref->{'DOMAINS'} };
        }
    }
    else {
        Cpanel::LoadModule::load_perl_module('Cpanel::Locale') if !$INC{'Cpanel/Locale.pm'};

        return ( 0, Cpanel::Locale->get_handle()->maketext('No user or domain is specified.') );
    }

    # Silently discard these as they will break dns
    @{$domains_ref} = grep { index( $_, '*' ) == -1 } @{$domains_ref};

    my $mainip = Cpanel::NAT::get_public_ip( Cpanel::DIp::MainIP::getmainserverip() );

    my $spf_match;
    if ( !$delete ) {
        my @zone;
        if ( $zone_ref && $zone_ref->{$domain} ) {
            @zone = ref $zone_ref->{$domain} ? @{ $zone_ref->{$domain} } : split( m{\n}, $zone_ref->{$domain} );
        }
        else {
            @zone = split( /\n/, Cpanel::DnsUtils::AskDnsAdmin::askdnsadmin( "GETZONE", 0, $domain ) );

        }
        @zone = grep ( !/^;/, @zone );
        my @records = grep( / \s+ TXT \s+ "? v=spf /x, @zone );

        #NOTE: This is ok as long as SPF records don't exceed 255 characters
        #or otherwise span multiple character strings.
        if ( $records[0] && $records[0] =~ / \s+ TXT \s+ "? ([^"]+) /x ) {
            $spf_match = $1;
        }
    }
    else {
        $overwrite = 1;
    }

    my @keys_list;
    if ($keys) {
        $keys =~ s{[^\w\s./:,-]+}{}g;

        #Trim and reject (a|mx):$domain
        @keys_list = map { s{\A\s+|\s+\z}{}g; m{\A(?:a|mx):\Q$domain\E\z}i ? () : $_ } split m{,}, $keys;
    }

    if ( $spf_match && $preserve ) {
        push @keys_list, grep { /:/ } split( / +/, $spf_match );
        $is_complete ||= ( $spf_match =~ / -all/ );
    }

    my @installlist;
    foreach my $domain ( @{$domains_ref} ) {
        push @installlist,
          {
            'match'       => 'v=spf',
            'removematch' => ( ( $overwrite || !$spf_match ) ? 'v=spf' : $spf_match ),
            'domain'      => $domain,
            'record'      => $domain,
            'value'       => make_spf_string( \@keys_list, undef, $is_complete, $domain ),
            'zone'        => $parent
          };
    }

    return Cpanel::DnsUtils::Install::install_txt_records( \@installlist, $domains_ref, $delete, $skipreload, $zone_ref );
}

1;
