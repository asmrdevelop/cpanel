package Cpanel::Net;

# cpanel - Cpanel/Net.pm                           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf8

=head1 NAME

Cpanel::Net

=head1 DESCRIPTION

This module contains methods related to Net tools.

=head1 SYNOPSIS

  use Cpanel::Net   ();

  # query a host
  my $array_ref = Cpanel::Net::host_lookup('example.com');

=head1 FUNCTIONS

=cut

use strict;
use warnings;

use Cpanel::Encoder::Tiny          ();
use Cpanel::Exception              ();
use Cpanel::FindBin                ();
use Cpanel::Locale                 ();
use Cpanel::SafeRun::Timed         ();
use Cpanel::Validate::Domain::Tiny ();

our $VERSION = '1.2';

sub Net_init { }

sub Net_sethastraceroute {
    my $tracer = Cpanel::FindBin::findbin( 'traceroute', 'path' => [ '/bin', '/sbin', '/usr/sbin', '/usr/local/sbin', '/usr/bin', '/usr/local/bin' ] );

    if ( !$tracer || !-x $tracer ) {
        $Cpanel::CPVAR{'Net_traceroute_disabled'} = 1;
    }
    else {
        $Cpanel::CPVAR{'Net_traceroute_disabled'} = 0;
    }
}

sub Net_traceroute { goto &traceroute; }

sub traceroute {
    return if ( !main::hasfeature('nettools') );

    if ( $Cpanel::CPDATA{'DEMO'} eq '1' ) {
        print Cpanel::Locale->get_handle->maketext('Sorry, this feature is disabled in demo mode.');
        return;
    }

    my $endpoint = $ENV{'REMOTE_HOST'} || $ENV{'REMOTE_ADDR'};
    $endpoint =~ s/;//g;

    print join( "\n", _traceroute($endpoint) );
    return '';
}

sub _traceroute {
    my $endpoint = shift;
    my $locale   = Cpanel::Locale->get_handle();
    my $tracer   = Cpanel::FindBin::findbin( 'traceroute', 'path' => [ '/bin', '/sbin', '/usr/sbin', '/usr/local/sbin', '/usr/bin', '/usr/local/bin' ] );
    if ( !$tracer || !-x $tracer ) {
        $Cpanel::CPERROR{'net'} = $locale->maketext('Traceroute is disabled on this system. Please ask your System Administrator to enable traceroute.');
        return ( $Cpanel::CPERROR{'net'} );
    }

    my $traceroute = Cpanel::SafeRun::Timed::timedsaferun( 60, $tracer, $endpoint );

    if ( !-x $tracer || $traceroute =~ /Operation not permitted/ ) {
        $Cpanel::CPERROR{'net'} = $locale->maketext('Traceroute is disabled on this system. Please ask your System Administrator to enable traceroute.');
        return ( $Cpanel::CPERROR{'net'} );
    }
    return ( split( /\n/, $traceroute ) );
}

sub Net_dnslookup { goto &dnslookup; }

sub dnslookup {
    return if ( !main::hasfeature('nettools') );

    if ( $Cpanel::CPDATA{'DEMO'} eq '1' ) {
        print Cpanel::Locale->get_handle->maketext('Sorry, this feature is disabled in demo mode.');
        return;
    }

    my $host = shift;
    if ( $host && Cpanel::Validate::Domain::Tiny::validdomainname($host) ) {
        my $output = Cpanel::Encoder::Tiny::safe_html_encode_str( Cpanel::SafeRun::Timed::timedsaferun( 60, '/usr/bin/host', $host ) );
        $output =~ s/\n/<br \/>\n/g;
        print $output;
    }
    else {
        print "Invalid zone.";
    }
    return;
}

=head2 host_lookup($host)

Query the given $host for DNS information.

=head3 ARGUMENTS

=over 1

=item $host

The FQDN of the host to query.

=back

=head3 RETURNS

On success, the method returns an arrayref containing the query result with one item per line.

=head3 EXCEPTIONS

=over

=item When the nettools feature is not enabled

=item When the account is in demo mode

=item When given an invalid host.

=item When the system fails to run the "host" command.

=item Other errors from additional modules used.

=back

=cut

sub host_lookup {

    my ($host) = @_;

    if ( !main::hasfeature('nettools') ) {
        die Cpanel::Exception::create( "FeatureNotEnabled", [ "feature_name" => 'nettools' ] );
    }

    if ( $Cpanel::CPDATA{'DEMO'} eq '1' ) {
        die Cpanel::Exception::create("ForbiddenInDemoMode");
    }

    if ( !$host || !Cpanel::Validate::Domain::Tiny::validdomainname( $host, 1 ) ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'You must specify a valid domain.' );
    }

    # FindBin warns, but errors are not translated.
    # This trap prevents them bubbling up to the UI
    local $SIG{__WARN__} = sub { };

    my $command = 'host';
    my $bin     = eval { Cpanel::FindBin::findbin($command) };
    die Cpanel::Exception::create( 'SystemCall', "The system failed to find the “[_1]” command.", [$command] ) if ( !$bin );

    my $output    = Cpanel::SafeRun::Timed::timedsaferun( 60, $bin, $host );
    my $exit_code = $? // 0;
    my @lines;

    if ($output) {
        die Cpanel::Exception->create( "The system was unable to track the domain that you entered. “[_1]”.", [$output] ) if $exit_code;
        @lines = split( /\n/, $output );
    }
    else {
        die Cpanel::Exception::create( 'SystemCall', "Unable to run the command “[_1]”.", [$command] );
    }

    return \@lines;
}

sub Net_dnszone { goto &dnszone; }

sub dnszone {
    my $host = shift;
    if ( $host && Cpanel::Validate::Domain::Tiny::validdomainname($host) ) {
        print Cpanel::Encoder::Tiny::safe_html_encode_str( _dnszone($host) );
    }
    else {
        print "Invalid zone.";
    }
    return;
}

sub api2_dnszone {
    my %CFG  = @_;
    my $host = $CFG{'host'};

    my @RSD;
    my @ZONE = grep( !/^\;/, split( /\n/, _dnszone($host) ) );

    foreach my $line (@ZONE) {
        chomp($line);
        next if ( $line =~ /^$/ );
        push( @RSD, { line => $line } );
    }
    return @RSD;
}

sub _dnszone {
    my $host = shift;
    return if ( !main::hasfeature('nettools') );

    if ( $Cpanel::CPDATA{'DEMO'} eq '1' ) {
        print Cpanel::Locale->get_handle->maketext('Sorry, this feature is disabled in demo mode.');
    }

    return Cpanel::SafeRun::Timed::timedsaferun( 60, 'dig', $host );
}

sub api2_traceroute {
    my (@RSD);

    my $endpoint = $ENV{'REMOTE_HOST'} || $ENV{'REMOTE_ADDR'};
    $endpoint =~ s/;//g;

    my @TR = _traceroute($endpoint);

    foreach (@TR) {
        chomp();
        push( @RSD, { line => $_ } );
    }
    return (@RSD);
}

our %API = (
    traceroute => {},
    dnszone    => { needs_feature => "nettools" },
);

sub api2 {
    my ($func) = @_;
    return { %{ $API{$func} } } if $API{$func};
    return;
}

1;
