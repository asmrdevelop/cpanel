package Whostmgr::TweakSettings::Basic;

# cpanel - Whostmgr/TweakSettings/Basic.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::Ips::Fetch                   ();
use Cpanel::Ips::V6                      ();
use Cpanel::Ips                          ();
use Cpanel::Sort                         ();
use Cpanel::StringFunc::Trim             ();
use Cpanel::Validate::EmailRFC           ();
use Cpanel::Validate::ICQUsername        ();
use Cpanel::Validate::NameServer         ();
use Cpanel::Validate::FilesystemNodeName ();
use Whostmgr::ThemeManager               ();
use Cpanel::Config::Constants            ();
use Cpanel::iContact::Providers          ();

#'Grouping' => {
#        'key' => {
#                'checkval' => sub{return shift;}, # scrub/sanitize; undef means invalid
#                'default' => 30,              # Value when $FORM{'key'} eq ''
#                'help' => 'Text to display',  # Description
#                'name' => 'A Friendly Name',  # More friendly name
#                'type' => 'number'            # Form type
#                'skipif' => sub {
#                        return 1 if ( condition ); # Don't show item
#                       return;                    # item will be shown
#                },
#                'action' => sub {             # return 1 for success 0 for failure
#                                   my $val = shift; # NEW value
#                                   my $oldval = shift; # OLD value
#                                   return 1 if ($val eq $oldval);
#                                   if ($val) { print "do stuff\n"; return 1;}
#                                   else { print "do other stuff\n"; return 1;}
#                },
#                'format' => sub { },  # How to present the data in the form
#                                      # NOTE: return undef means "disabled"
#                'unit' => MB, KB, &, etc.
#        }
#},

our @warnings;
our %Conf = (
    Cpanel::iContact::Providers::get_settings(),
    'ADDR' => {
        'type'      => 'text',
        'maxlength' => 15,
        'checkval'  => sub {
            my $value = shift();
            $value =~ s{\s+}{}g;

            require Cpanel::Validate::IP::v4;
            if ( !Cpanel::Validate::IP::v4::is_valid_ipv4($value) ) {
                return ( undef, "Address ($value) is not a valid IPv4 address." );
            }
            if ( ( index( $value, '.' ) == 3 ) && ( substr( $value, 0, 3 ) >= 224 ) && ( substr( $value, 0, 3 ) < 240 ) ) {
                return ( undef, "Multicast address ($value) is not valid for this setting." );
            }
            else {
                if ( !defined Cpanel::Ips::Fetch::fetchipslist()->{$value} && $value ne '127.0.0.1' ) {
                    push @warnings, [ 'ADDR', 'addr_external_ip', ];
                }

                return $value;
            }
        },
    },
    'ADDR6' => {
        'type'      => 'text',
        'size'      => 25,
        'maxlength' => 39,
        'checkval'  => sub {
            my $value = lc( shift() );
            $value =~ s{\s+}{}g;

            # allow empty value to clear the field #
            return '' if !$value;

            # verify that an valid IPv6 address was entered #
            my $ipv6_flat;
            if ( $ipv6_flat = Cpanel::Ips::V6::validate_ipv6($value) ) {
                my @ips = grep( $_ eq $ipv6_flat, map { Cpanel::Ips::V6::validate_ipv6($_) } Cpanel::Ips::V6::fetchipv6list() );
                return ( undef, 'The address is not bound to this server.' ) unless @ips;

                require Cpanel::CPAN::Net::IP;
                require Cpanel::IPv6::Utils;

                my $range      = Cpanel::CPAN::Net::IP->new( $value, 6 );
                my $overlapped = Cpanel::IPv6::Utils::range_overlaps_existing( $range, 0, undef, { smallest => 1 } );
                return ( undef, "The range overlaps with another existing range: $overlapped" ) if $overlapped;

                return $value;
            }

            return ( undef, 'The address is not a valid IPv6 address.' );
        },
    },
    'CONTACTEMAIL' => {
        'type'     => 'text',
        'checkval' => sub {
            my $value = shift();
            $value = Cpanel::StringFunc::Trim::ws_trim($value);

            my @addresses = split m{[\s,;]+}, $value;

            return ( grep { !Cpanel::Validate::EmailRFC::is_valid_remote($_) } @addresses )
              ? ()
              : join( ',', @addresses );
        },
    },
    'EMAILFROMNAME' => {
        'type'     => 'text',
        'checkval' => sub {
            my ($val) = @_;
            $val = Cpanel::StringFunc::Trim::ws_trim($val);

            # https://datatracker.ietf.org/doc/html/rfc822#section-3.4.5
            return ( $val !~ m/[\\"\r\n]+/ ) ? $val : undef;
        },
    },
    'EMAILREPLYTO' => {
        'type'     => 'text',
        'checkval' => sub {
            my ($val) = @_;
            $val = Cpanel::StringFunc::Trim::ws_trim($val);

            return $val if $val eq q{};

            return Cpanel::Validate::EmailRFC::is_valid_remote($val) ? $val : undef;
        },
    },
    'CONTACTPUSHBULLET' => {
        'type'     => 'text',
        'checkval' => sub {
            my $value = shift();
            $value = Cpanel::StringFunc::Trim::ws_trim($value);

            return $value if $value eq q{};

            return Cpanel::Validate::FilesystemNodeName::is_valid($value)
              ? $value
              : ();
        },
    },
    'CONTACTUIN' => {
        'type'     => 'text',
        'checkval' => sub {
            my $value = shift();
            $value = Cpanel::StringFunc::Trim::ws_trim($value);

            return $value if $value eq q{};

            my @usernames = split m{[\s,;]+}, $value;

            return ( grep { !Cpanel::Validate::ICQUsername::is_valid($_) } @usernames )
              ? ()
              : join( ',', @usernames );
        },
    },
    'ICQUSER' => {
        'type'     => 'text',
        'checkval' => sub {
            my $value = shift();
            $value = Cpanel::StringFunc::Trim::ws_trim($value);

            return $value if $value eq q{};

            return Cpanel::Validate::ICQUsername::is_valid($value)
              ? $value
              : ();
        },
    },
    'ICQPASS' => {
        'type' => 'password',
    },
    'HOMEDIR' => {
        'type'     => 'text',
        'default'  => '/home',
        'checkval' => sub {
            my $value = shift();

            $value =~ s{\s+}{}g;
            chop($value) if substr( $value, -1 ) eq '/';

            return $value;
        },
    },
    'HOMEMATCH' => {
        'type'    => 'text',
        'default' => 'home',
    },
    'DEFMOD' => {
        'type'    => 'select',
        'default' => $Cpanel::Config::Constants::DEFAULT_CPANEL_THEME,
        'options' => [ $Whostmgr::ThemeManager::APPS{'cpanel'}{'themelistfunc'}->() ],
        'skipif'  => sub {
            return scalar $Whostmgr::ThemeManager::APPS{'cpanel'}{'themelistfunc'}->() <= 1;
        }
    },
    'TTL' => {
        'type'      => 'text',
        'default'   => 14400,
        'maxlength' => 10,
        'checkval'  => sub {
            my $value = shift();
            $value =~ s{\s+}{}g;

            return $value =~ m{\A\d+\z} && $value <= 2147483647
              ? $value
              : ();
        },
    },
    'LOGSTYLE' => {
        needs_role => 'WebServer',
        'type'     => 'radio',
        'default'  => 'combined',
        'options'  => [ 'combined', 'common', ],
    },
    'ETHDEV' => {
        'type'     => 'select',
        'options'  => [ grep { !m{\d+:} } keys %{ Cpanel::Ips::fetchiflist() } ],
        'checkval' => sub {
            my ($value) = @_;
            $value =~ s{\s+}{}g;
            if ( $value eq 'lo' ) {
                return;
            }
            if ( $value =~ m{\A[a-zA-Z]+[a-zA-Z0-9]*(?:\.[0-9]+)?[:0-9]*\z} ) {
                return $value;
            }
            return;
        },
        'allow_other' => 1,
        'width'       => 7,
        'sorter'      => sub {
            return Cpanel::Sort::list_sort(
                shift(),
                sub { m{(\D+)} && $1 },    #sort alphabetically first
                { 'num' => 1, 'code' => sub { m{(\d+)} && $1 || 0 }, },
            );
        },
    },
    'SCRIPTALIAS' => {
        needs_role => 'WebServer',

        #migrate this to a "binary" (0/1) setting eventually
        'type'    => 'radio',
        'default' => 'y',
        'options' => [qw( y n )],
        'format'  => sub { return lc shift(); },
    },
    'NS' => {
        'type'     => 'text',
        'checkval' => sub {
            my ($value) = @_;
            $value = Cpanel::Validate::NameServer::normalize($value);
            if ($value) {
                return Cpanel::Validate::NameServer::is_valid($value) ? $value : ();
            }
            return q{};    #We consider empty string a valid value.
        },
    },
);

#necessary to make copies, not just set the references
$Conf{'CONTACTPAGER'} = { %{ $Conf{'CONTACTEMAIL'} } };
$Conf{'NSTTL'}        = { %{ $Conf{'TTL'} }, 'default' => 86400, };

foreach my $ns (qw( NS2 NS3 NS4 )) {
    $Conf{$ns} = { %{ $Conf{'NS'} } };
}

1;
