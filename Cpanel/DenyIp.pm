package Cpanel::DenyIp;

# cpanel - Cpanel/DenyIp.pm                        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf8

=head1 NAME

Cpanel::DenyIp

=head1 DESCRIPTION

This module is used to manage which IP addresses are blocked for web access to domains on the cPanel account.

=head1 FUNCTIONS

=cut

use strict;
use warnings;

use Cpanel                                ();
use Cpanel::BitConvert                    ();
use Cpanel::DomainLookup                  ();
use Cpanel::Encoder::Tiny                 ();
use Cpanel::Exception                     ();
use Cpanel::HttpUtils::Htaccess           ();
use Cpanel::Logger                        ();
use Cpanel::SocketIP                      ();
use Cpanel::IP::Convert                   ();
use Cpanel::Validate::IP                  ();
use Cpanel::Validate::IP::v4              ();
use Cpanel::Locale                        ();
use Cpanel::Server::Type::Role::WebServer ();

our $VERSION = '2.3';

my $locale;
my $logger = Cpanel::Logger->new();

sub _HtaccessCompatCheck {
    my $docrootslist_ref = Cpanel::DomainLookup::getdocrootlist();
    foreach my $docroot ( keys %{$docrootslist_ref} ) {
        my $htaccess_trans = Cpanel::HttpUtils::Htaccess::open_htaccess_rw($docroot);
        my $htaccess_sr    = $htaccess_trans->get_data();

        my $has_403_exception = $$htaccess_sr =~ m<403\.shtml>;

        my @HTACCESS;

        if ( !$has_403_exception ) {
            my $inlimit = 0;
            my $fixed   = 0;
          HTACCESSLOOP:
            while ( $$htaccess_sr =~ m<([^\n]*\n?)>g ) {
                my $line = $1;
                if ( $line =~ m/^\s*<Limit\s+GET/i ) {

                    #we only want to modify the GET and POST limits
                    #the limit on PUT and DELETE should be denied to everyone
                    $inlimit = 1;
                }
                elsif ( $line =~ m/^\s*<\/Limit/i ) {
                    $inlimit = 0;
                }
                elsif ( $inlimit && $line =~ m/^\s*order\s+deny,\s*allow/ ) {
                    push @HTACCESS, "#The next line modified by DenyIP\n";
                    push @HTACCESS, "order allow,deny\n";
                    $fixed++;
                    next HTACCESSLOOP;
                }
                elsif ( $inlimit && $line =~ m/^\s*deny\s+from\s+all/ ) {
                    push @HTACCESS, "#The next line modified by DenyIP\n";
                    push @HTACCESS, "#deny from all\n";
                    $fixed++;
                    next HTACCESSLOOP;
                }
                push @HTACCESS, $line;
            }
            if ( !$has_403_exception ) {
                push @HTACCESS, "\n<Files 403.shtml>\n";
                push @HTACCESS, "order allow,deny\n";
                push @HTACCESS, "allow from all\n";
                push @HTACCESS, "</Files>\n\n";
            }

            $htaccess_trans->set_data( \join( q<>, @HTACCESS ) );
            $htaccess_trans->save_and_close_or_die();
        }
        else {
            $htaccess_trans->close_or_die();
        }
    }
}

sub _listdenyips {
    my $htaccess_trans = Cpanel::HttpUtils::Htaccess::open_htaccess_ro("$Cpanel::homedir/public_html");
    my $htaccess_sr    = $htaccess_trans->get_data();

    my @BLOCKIPS;
    my $inlimit = 0;

    my $line;

  HTACCESSLOOP:
    while ( defined $$htaccess_sr && $$htaccess_sr =~ m<([^\n]*\n?)>g ) {
        $line = $1;
        if ( $line =~ m/<limit/i ) { $inlimit = 1; }
        if ( !$inlimit && $line !~ m/^\s*#/ ) {
            chomp $line;
            if ( $line =~ /^\s*deny\s+from\s+(\S+)/i ) {
                my $bip = $1;
                $bip =~ s/\r//g;
                if ($bip) {
                    if ( $bip =~ /\// || $bip =~ /\.$/ ) {
                        my ( $ip, $cidr );
                        my $range;
                        my @IP;
                        if ( $bip =~ /\// ) {
                            ( $ip, $cidr ) = split( /\//, $bip );
                            if ( $cidr =~ /\./ ) {
                                $range = Cpanel::BitConvert::mask2cidr($cidr);
                            }
                            else {
                                $range = $bip;
                            }
                        }
                        else {
                            $ip = $bip;
                            $ip =~ s/\.$//g;
                            @IP   = split( /\./, $ip );
                            $cidr = ( $#IP + 1 ) * 8;
                            while ( $#IP < 3 ) {
                                push @IP, '0';
                            }
                            $range = join( '.', @IP );
                        }

                        my ( $start, $end ) = map { Cpanel::IP::Convert::binip_to_human_readable_ip($_) } Cpanel::IP::Convert::ip_range_to_start_end_address($range);
                        push( @BLOCKIPS, { ip => $bip, start => $start, end => $end, range => "$start-$end" } );
                    }
                    else {
                        next unless Cpanel::Validate::IP::is_valid_ip($bip);
                        push( @BLOCKIPS, { ip => $bip, start => $bip, end => $bip, range => $bip } );
                    }
                    next HTACCESSLOOP;
                }
            }
        }
        if ( $line =~ /<\/limit/i ) { $inlimit = 0; }
    }

    return @BLOCKIPS;
}

sub DenyIp_adddenyip {
    my ( $ip, $quiet ) = @_;

    return if !_role_and_feature_are_ok();

    if ( $Cpanel::CPDATA{'DEMO'} eq '1' ) {
        $Cpanel::CPERROR{'denyip'} = "Sorry, this feature is disabled in demo mode.";
        print "Sorry, this feature is disabled in demo mode.";
        return;
    }

    $ip =~ s/\*.*//g;

    _HtaccessCompatCheck();

    # Provided a hostname, not an IP
    if ( !_is_valid_ipish($ip) ) {
        my $host = $ip;
        $ip = Cpanel::SocketIP::_resolveIpAddress($ip);
        if ( $ip ne '0' ) {
            print Cpanel::Encoder::Tiny::safe_html_encode_str($host) . " was resolved to the IP address " . Cpanel::Encoder::Tiny::safe_html_encode_str($ip) . ". " if !$quiet;
        }
        else {
            print "Sorry. The hostname that you entered could not be resolved to a valid IP address.\n" if !$quiet;
            $Cpanel::CPERROR{'denyip'} = 'Sorry. The hostname you entered could not be resolved to a valid IP address.';
            return;
        }
    }

    my @IPLIST = _get_ip_list_from_input_ip($ip);
    if ( !@IPLIST ) {
        $Cpanel::CPERROR{"denyip"} = _locale()->maketext( "The IP address range “[_1]” is not valid.", $ip );
        return;

    }

    my $docrootslist_ref = Cpanel::DomainLookup::getdocrootlist();
    foreach my $docroot ( keys %{$docrootslist_ref} ) {
        if ( $docroot =~ m/^\/usr\/local\/apache/ ) { next; }

        my $htaccess_trans = Cpanel::HttpUtils::Htaccess::open_htaccess_rw($docroot);
        my $htaccess_sr    = $htaccess_trans->get_data();

        # add newline if last line doesn’t contain one
        $$htaccess_sr .= "\n" if substr( $$htaccess_sr, -1 ) ne "\n";

        foreach my $ip (@IPLIST) {
            if ( $$htaccess_sr !~ m/^\s*deny\s+from\s+\Q$ip\E\s*$/m ) {

                $$htaccess_sr .= "deny from $ip\n";
            }
        }

        $htaccess_trans->save_and_close_or_die();
    }

    if (@IPLIST) {
        foreach my $ip (@IPLIST) {
            print "Users from the IP address(es) " . Cpanel::Encoder::Tiny::safe_html_encode_str($ip) . " will not be able to access your site. <br />" if !$quiet;
        }
    }
    else {
        print "No valid IP addresses were specified. <br />" if !$quiet;
    }
    return 1;
}

=head2 add_ip($ip)

Add 'deny from' entries to the users .htaccess file to prevent
access to web resources.

=head3 ARGUMENTS

=over 1

=item $ip

The IP address, hostname, CIDR range, implied range, or wildcard range
of addresses to deny. Uses L<Cpanel::SocketIP> for hostname
resolution and L<Cpanel::IP::Convert> for range resolution.

=over 1

=item 192.168.0.1 - Single IPv4 Address

=item 2001:db8::1 - Single IPv6 Address

=item 192.168.0.1-192.168.0.58 - IPv4 Range

=item 2001:db8::1-2001:db8::3 - IPv6 Range

=item 192.168.0.1-58 - Implied Range

=item 192.168.0.1/16 - CIDR Format IPv4

=item 2001:db8::/32 - CIDR Format IPv6

=item 10. - Matches 10.*.*.*

=back

=back


=head3 RETURNS

On success, the method returns an arrayref containing the IP addresses added.

=head3 EXCEPTIONS

=over

=item When the WebServer Role or ipdeny feature are not enabled

=item When the account is in demo mode

=item When a hostname cannot be resolved.

=item When given invalid IP's or ranges.

=item Other errors from additional modules used.

=back

=cut

sub add_ip {
    my ($ip) = @_;

    if ( !_role_and_feature_are_ok() ) {
        die Cpanel::Exception::create( 'FeatureNotEnabled', [ feature_name => 'ipdeny' ] );
    }

    if ( $Cpanel::CPDATA{'DEMO'} eq '1' ) {
        die Cpanel::Exception::create('ForbiddenInDemoMode');
    }

    $ip =~ s/\*.*//g;

    _HtaccessCompatCheck();

    # Provided a hostname, not an IP
    if ( !_is_valid_ipish($ip) ) {
        my $host = $ip;
        $ip = Cpanel::SocketIP::_resolveIpAddress($ip);

        if ( $ip eq '0' ) {
            die Cpanel::Exception::create( 'InvalidParameter', 'The host name “[_1]” does not resolve to any [asis,IPv4] addresses.', [$host] );
        }
    }

    my @IPLIST = _get_ip_list_from_input_ip($ip);
    if ( !@IPLIST ) {
        die Cpanel::Exception::create( 'InvalidParameter', "The IP address range “[_1]” is not valid.", [$ip] );
    }

    my $docrootslist_ref = Cpanel::DomainLookup::getdocrootlist();
    foreach my $docroot ( keys %{$docrootslist_ref} ) {
        if ( $docroot =~ m/^\/usr\/local\/apache/ ) { next; }

        my $htaccess_trans = Cpanel::HttpUtils::Htaccess::open_htaccess_rw($docroot);
        my $htaccess_sr    = $htaccess_trans->get_data();

        # add newline if last line doesn’t contain one
        $$htaccess_sr .= "\n" if substr( $$htaccess_sr, -1 ) ne "\n";

        foreach my $address (@IPLIST) {
            if ( $$htaccess_sr !~ m/^\s*deny\s+from\s+\Q$address\E\s*$/m ) {

                $$htaccess_sr .= "deny from $address\n";
            }
        }

        $htaccess_trans->save_and_close_or_die();
    }

    return @IPLIST ? \@IPLIST : [];
}

sub DenyIp_deldenyip {
    my $ip = shift;

    return if !_role_and_feature_are_ok();

    if ( $Cpanel::CPDATA{'DEMO'} eq "1" ) {
        $Cpanel::CPERROR{'denyip'} = "Sorry, this feature is disabled in demo mode.";
        print "Sorry, this feature is disabled in demo mode.";
        return;
    }

    if ( !$ip || !Cpanel::Validate::IP::is_valid_ip_cidr_or_prefix($ip) ) {
        print "<b>Error: invalid argument, requires IP</b>\n";
        $Cpanel::CPERROR{"denyip"} = "Error: invalid argument, requires IP";
        return;
    }

    my $docrootslist_ref = Cpanel::DomainLookup::getdocrootlist();
    foreach my $docroot ( keys %{$docrootslist_ref} ) {
        my $htaccess_trans = Cpanel::HttpUtils::Htaccess::open_htaccess_rw($docroot);
        my $htaccess_sr    = $htaccess_trans->get_data();

        $$htaccess_sr =~ s<^\s*deny\s+from\s+\Q$ip\E\s*$><>im;

        $htaccess_trans->save_and_close_or_die();
    }
    return;
}

=head2 remove_ip($ip)

Remove 'deny from' entries to the users .htaccess file to allow
access to web resources.

=head3 ARGUMENTS

=over 1

=item $ip

The IP address, hostname, CIDR range, implied range, or wildcard range
of addresses to allow. Uses L<Cpanel::SocketIP> for hostname
resolution and L<Cpanel::IP::Convert> for range resolution.

=over 1

=item 192.168.0.1 - Single IPv4 Address

=item 2001:db8::1 - Single IPv6 Address

=item 192.168.0.1-192.168.0.58 - IPv4 Range

=item 2001:db8::1-2001:db8::3 - IPv6 Range

=item 192.168.0.1-58 - Implied Range

=item 192.168.0.1/16 - CIDR Format IPv4

=item 2001:db8::/32 - CIDR Format IPv6

=item 10. - Matches 10.*.*.*

=back

=back


=head3 RETURNS

On success, the method returns an arrayref containing the IP addresses removed.

=head3 EXCEPTIONS

=over

=item When the WebServer Role or ipdeny feature are not enabled

=item When the account is in demo mode

=item When a hostname cannot be resolved.

=item When given invalid IP's or ranges.

=item Other errors from additional modules used.

=back

=cut

sub remove_ip {
    my ($ip) = @_;

    if ( !_role_and_feature_are_ok() ) {
        die Cpanel::Exception::create( 'FeatureNotEnabled', [ feature_name => 'ipdeny' ] );
    }

    if ( $Cpanel::CPDATA{'DEMO'} eq '1' ) {
        die Cpanel::Exception::create('ForbiddenInDemoMode');
    }

    $ip =~ s/\*.*//g;

    # Provided a hostname, not an IP
    if ( !_is_valid_ipish($ip) ) {
        my $host = $ip;
        $ip = Cpanel::SocketIP::_resolveIpAddress($ip);

        if ( $ip eq '0' ) {
            die Cpanel::Exception::create( 'InvalidParameter', 'The host name “[_1]” does not resolve to any [asis,IPv4] addresses.', [$host] );
        }
    }

    my @IPLIST = _get_ip_list_from_input_ip($ip);
    if ( !@IPLIST ) {
        die Cpanel::Exception::create( 'InvalidParameter', "The IP address range “[_1]” is not valid.", [$ip] );
    }

    my $docrootslist_ref = Cpanel::DomainLookup::getdocrootlist();
    foreach my $docroot ( keys %{$docrootslist_ref} ) {
        my $htaccess_trans = Cpanel::HttpUtils::Htaccess::open_htaccess_rw($docroot);
        my $htaccess_sr    = $htaccess_trans->get_data();

        foreach my $address (@IPLIST) {
            $$htaccess_sr =~ s<^\s*deny\s+from\s+\Q$address\E\s*$><>im;
        }

        $htaccess_trans->save_and_close_or_die();
    }

    return @IPLIST ? \@IPLIST : [];
}

sub DenyIp_listdenyips {
    return if !_role_and_feature_are_ok();

    my @IPS = _listdenyips();
    foreach (@IPS) {
        print Cpanel::Encoder::Tiny::safe_html_encode_str( $_->{'ip'} ) . "\n";
    }

    return;
}

sub _role_and_feature_are_ok {
    return if !Cpanel::Server::Type::Role::WebServer->is_enabled();
    return main::hasfeature("ipdeny");
}

our %API = (
    'listdenyips' => {
        'func'       => '_listdenyips',
        'needs_role' => 'WebServer',
        allow_demo   => 1,
    },
);

sub api2 {
    my ($func) = @_;
    return { %{ $API{$func} } } if $API{$func};
    return;
}

my $_locale;

sub _locale {
    return $_locale ||= do {
        Cpanel::Locale->get_handle();
    };
}

# Does this look something like an IP, CIDR, prefix, range, or other address?
sub _is_valid_ipish {
    my ($ip) = @_;
    return Cpanel::Validate::IP::is_valid_ip_range_cidr_or_prefix($ip) || $ip =~ m/^(\d+\.){1,3}$/;
}

sub _get_ip_list_from_input_ip {
    my ($input_ip) = @_;
    if ( $input_ip !~ tr{:}{} && scalar split( m{\.}, $input_ip ) < 4 ) {
        my ( $new_start_ip, $new_end_ip ) = Cpanel::IP::Convert::wildcard_address_to_range($input_ip);
        if ( !Cpanel::Validate::IP::v4::is_valid_ipv4($new_start_ip) || !Cpanel::Validate::IP::v4::is_valid_ipv4($new_end_ip) ) {
            return;
        }

        $input_ip = join( '-', $new_start_ip, $new_end_ip );
    }
    if ( $input_ip =~ m{-} ) {
        my ( $start_ip, $end_ip ) = split( m{-}, $input_ip, 2 );

        my $new_start_ip = Cpanel::IP::Convert::implied_range_to_full_range( $start_ip, $end_ip );
        my $new_end_ip   = Cpanel::IP::Convert::implied_range_to_full_range( $end_ip,   $start_ip );

        if ( !Cpanel::Validate::IP::is_valid_ip($new_start_ip) || !Cpanel::Validate::IP::is_valid_ip($new_end_ip) ) {
            return;
        }

        $input_ip = join( '-', $new_start_ip, $new_end_ip );
    }

    my ( $start_address, $end_address ) = Cpanel::IP::Convert::ip_range_to_start_end_address($input_ip);

    if ( !$end_address || !$start_address ) {
        return;
    }

    return map {
        my $r = $_;
        $r =~ s{^([\d.]+)\/32$}{$1};
        $r =~ s{^([\da-fA-F:]+)\/128$}{$1};
        $r;
    } Cpanel::BitConvert::convert_iprange_cidrs( Cpanel::IP::Convert::binip_to_human_readable_ip($start_address), Cpanel::IP::Convert::binip_to_human_readable_ip($end_address) );
}

1;
