package Whostmgr::DNS::Domains;

# cpanel - Whostmgr/DNS/Domains.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::DIp::MainIP           ();
use Cpanel::NAT                   ();
use Cpanel::DnsUtils::Stream      ();
use Cpanel::Validate::Domain      ();
use Cpanel::DnsUtils::AskDnsAdmin ();

sub delsubdomain {
    my ( $main_domain, $sub_domain, $force ) = @_;

    # TODO see case 10634, this will eventually be a more sensible function and not a counter intuitive add-to-delete call
    #      (IE not add a subdomain to get it removed, not need 'do_not_create_zone', and, remove A record for multi level subdomains)
    # !!!! don't remove it yet !!!!

    return addsubdomain(
        '', '', '', '',
        {
            'do_not_create_zone' => 1,
            'sub'                => $sub_domain,
            'allowoverwrite'     => $force,
            'domain'             => "$main_domain.db",
            'addwww'             => 1,
            'readd'              => 0,
            'cpanel'             => 1
        },
    );
}

# FIXME: this should not print(), it should only return
sub addsubdomain {    ## no critic qw(Subroutines::ProhibitExcessComplexity)
    my ( $sub, $domain, $ip, $addwww, $ropts ) = @_;
    my %OPTS;
    if ( ref $ropts eq 'HASH' ) {
        %OPTS = %{$ropts};
    }

    if ( exists $OPTS{'sub'} && defined $OPTS{'sub'} ) {
        $sub = $OPTS{'sub'};
    }
    my $adviseip = '';
    if ( $OPTS{'adviseip'} && $OPTS{'adviseip'} =~ /(\d+\.\d+\.\d+\.\d+)/ ) {
        $adviseip = $1;
    }

    my $allowoverwrite = int( $OPTS{'allowoverwrite'} || 0 );
    $sub =~ s/[^\*\w\-\.]//g;

    if ( $sub =~ m/\*/ ) {
        if ( !Cpanel::Validate::Domain::is_valid_wildcard_domain("$sub.$domain") ) {
            my $msg = "invalid wildcard domain: “$sub.$domain”";
            return ( 0, $msg ) if wantarray;
            warn $msg;
            return 0;
        }
    }

    chomp( $OPTS{'domain'} ) if defined $OPTS{'domain'};
    if ( length $OPTS{'domain'} ) {
        $domain = $OPTS{'domain'};
    }
    $domain =~ s/\.\.//g;
    $domain =~ s/\///g;
    $domain =~ s/\.db$//g;
    my $zonef = $domain . '.db';

    if ( !length $addwww ) {
        $addwww = $OPTS{'addwww'};
    }

    if ( $sub =~ /\*/ ) { $addwww = 0; }

    my @ZONE;
    my $zonedata = Cpanel::DnsUtils::AskDnsAdmin::askdnsadmin( 'GETZONE', 0, $domain );

    if ( !$zonedata ) {
        if ( !$OPTS{'do_not_create_zone'} ) {
            print "The zone for the root domain $domain is missing, or could not be read.  The IP address will be read from the webserver configuration and a new zone will be created for this subdomain.\n";
            if ($adviseip) {
                $ip = $adviseip;
            }
            if ( $ip !~ m/^\d+[.]\d+[.]\d+[.]\d+$/ ) {
                $ip = Cpanel::DIp::MainIP::getmainip();
            }
            if ( addsimplezone( $domain, Cpanel::NAT::get_public_ip($ip), $allowoverwrite, $OPTS{'has_ipv6'}, $OPTS{'ipv6'} ) ) {
                $zonedata = Cpanel::DnsUtils::AskDnsAdmin::askdnsadmin( 'GETZONE', 0, $domain );
            }
            if ( !$zonedata ) {
                print "Unable to add record for $domain\n";
                return;
            }
        }
        else {
            warn "No zone data for “$domain” is available, and “do_not_create_zone” was passed!";
            return;
        }
    }

    # Only search for the magic subdomainip subdomain if the text exists
    if ( length $OPTS{'cpanel'} && $OPTS{'cpanel'} eq "1" && index( $zonedata, "subdomainip" ) > -1 && $zonedata =~ m{^[ \t]*subdomainip}m ) {
        @ZONE = split( m{\n}, $zonedata ) if !@ZONE;
        $ip   = getsubzoneip( "subdomainip", @ZONE );
    }

    if ( $ip eq "" ) {

        # If the caller 'suggested' an address, use that rather than the root domain's address
        # since the root domain might actually be on some other server
        $ip = $adviseip;
    }
    if ( $ip eq "" ) {
        @ZONE = split( m{\n}, $zonedata ) if !@ZONE;
        $ip   = getzoneip( $domain, @ZONE );
    }
    if ( $ip eq "" ) {
        return (0);
    }

    my $public_ip = Cpanel::NAT::get_public_ip($ip);

    if ( index( $zonedata, $sub ) > -1 ) {
        @ZONE = split( m{\n}, $zonedata ) if !@ZONE;

        # remove existing entries
        my $remove_regex = quotemeta($sub) . '|' . quotemeta("$sub.$domain");
        if ($addwww) {
            $remove_regex .= '|' . quotemeta("www.$sub") . '|' . quotemeta("www.$sub.$domain");
        }
        @ZONE     = eval 'grep(!m{^[ \t]*(?:' . $remove_regex . ')[ \t]+}, @ZONE)';    ## no critic qw(BuiltinFunctions::ProhibitStringyEval) -- avoid regex recomp on each iteration
        $zonedata = join( "\n", @ZONE );
    }

    if ( !length $OPTS{'readd'} || $OPTS{'readd'} ne "0" ) {
        $zonedata .= "\n" if substr( $zonedata, -1, 1 ) ne "\n";
        $zonedata .= "$sub IN A  $public_ip\n";
        $zonedata .= "$sub IN AAAA  $OPTS{'ipv6'}\n" if $OPTS{'has_ipv6'};
        if ($addwww) {
            $zonedata .= "www.${sub} IN A  $public_ip\n";
            $zonedata .= "www.${sub} IN AAAA  $OPTS{'ipv6'}\n" if $OPTS{'has_ipv6'};
        }
    }

    $zonedata = Cpanel::DnsUtils::Stream::upsrnumstream($zonedata);
    print Cpanel::DnsUtils::AskDnsAdmin::askdnsadmin( "SAVEZONE", 0, $domain, $zonedata );
    if ( !$OPTS{'nodnsreload'} ) { print Cpanel::DnsUtils::AskDnsAdmin::askdnsadmin( "RELOADBIND", 0, $domain ); }

    return ( 1, $ip );
}

sub getzoneip {
    my ( $domain, @ZONE ) = @_;
    if ( ref $ZONE[0] eq 'ARRAY' ) {
        @ZONE = @{ $ZONE[0] };
    }
    my ( $s1, $s2, $s3, $s4, $s5 );
    foreach my $line (@ZONE) {
        if ( $line =~ /(\S+)[\t|\s]*(\S+)[\t|\s]*(\S*)[\t|\s]*(\S*)[\t|\s]*(\S*)[\t|\s]*(\S*)[\t|\s]*(\S*)/ ) {
            $s1 = $1;
            $s2 = $2;
            $s3 = $3;
            $s4 = $4;
            $s5 = $5;
            if ( $s1 eq "A" || $s2 eq "A" || $s3 eq "A" || $s4 eq "A" ) {
                if ( $s1 eq "A" && $s3 eq "" ) { return ($s2); }

                if ( $s1 =~ /^\d+$/ && $s2 !~ /^\d+$/ ) {
                    $s5 = $s4;
                    $s4 = $s3;
                    $s3 = $s2;
                    $s2 = $s1;
                    $s1 = '';
                }
                if ( $s2 eq "IN" ) {
                    $s5 = $s4;
                    $s4 = $s3;
                    $s3 = $s2;
                    $s2 = 14400;
                }
                if ( $s3 ne "IN" ) {
                    $s5 = $s4;
                    $s4 = $s3;
                    $s3 = 'IN';
                    $s2 = 14400;
                }
                if ( $s2 !~ /^\d+$/ ) {
                    $s5 = $s4;
                    $s4 = $s3;
                    $s3 = $s2;
                    $s2 = 14400;
                }
                if ( $s1 eq "" ) {
                    return ($s5);
                }
                if ( $s1 eq "${domain}." || $s1 eq '@' ) {
                    return ($s5);
                }
            }
        }
    }
    return;
}

sub getsubzoneip {
    my ( $sub, @ZONE ) = @_;

    my ( $s1, $s2, $s3, $s4, $s5 );
    foreach my $line (@ZONE) {
        if ( $line =~ /(\S+)[\t|\s]*(\S+)[\t|\s]*(\S*)[\t|\s]*(\S*)[\t|\s]*(\S*)[\t|\s]*(\S*)[\t|\s]*(\S*)/ ) {
            ( $s1, $s2, $s3, $s4, $s5 ) = ( $1, $2, $3, $4, $5 );
            if ( $s1 eq "A" || $s2 eq "A" || $s3 eq "A" || $s4 eq "A" ) {
                if ( $s1 eq "A" && $s3 eq "" ) { return ($s2); }

                if ( $s1 =~ /^\d+$/ && $s2 !~ /^\d+$/ ) {
                    $s5 = $s4;
                    $s4 = $s3;
                    $s3 = $s2;
                    $s2 = $s1;
                    $s1 = '';
                }
                if ( $s2 eq "IN" ) {
                    $s5 = $s4;
                    $s4 = $s3;
                    $s3 = $s2;
                    $s2 = 14400;
                }
                if ( $s3 ne "IN" ) {
                    $s5 = $s4;
                    $s4 = $s3;
                    $s3 = 'IN';
                    $s2 = 14400;
                }
                if ( $s2 !~ /^\d+$/ ) {
                    $s5 = $s4;
                    $s4 = $s3;
                    $s3 = $s2;
                    $s2 = 14400;
                }
                if ( $s1 eq "" ) {
                    return ($s5);
                }
                if ( $s1 eq $sub ) {
                    return ($s5);
                }
            }
        }
    }

    return "";
}

sub addsimplezone {
    my ( $domain, $ip, $allowoverwrite, $has_ipv6, $ipv6 ) = @_;

    require Cpanel::DnsUtils::Add;
    my ( $result, $reason ) = Cpanel::DnsUtils::Add::doadddns(
        'domain'         => $domain,
        'ip'             => $ip,
        'allowoverwrite' => $allowoverwrite,
        'template'       => 'simple',
        'has_ipv6'       => $has_ipv6,
        'ipv6'           => $ipv6
    );

    print $reason . "\n";

    if ($result) {
        print "<br />\nCreated DNS entry for $domain\n";
        print "<br />\n";
    }

    return $result;
}

1;
