
# cpanel - Cpanel/DNSLib/Zone.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::DNSLib::Zone;

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings)

use Cpanel::Autowarn        qw( unlink );
use Cpanel::SafeRun::Errors ();
use Cpanel::Logger          ();

# NB: Consider Cpanel::DnsUtils::CheckZone instead, which accepts a
# buffer rather than a filesystem path.
sub checkzone {
    my $zone     = shift;
    my $zonefile = shift;

    if ( !$zone ) {
        return wantarray ? ( 0, 'No zone specified' ) : 0;
    }
    elsif ( $zone !~ m/[\w\.]+/ ) {
        return wantarray ? ( 0, "Invalid zone $zone specified" ) : 0;
    }
    elsif ( !$zonefile ) {
        return wantarray ? ( 0, 'No zone file specified' ) : 0;
    }
    elsif ( !-e $zonefile || -z _ ) {
        return wantarray ? ( 0, "No zone file located at $zonefile" ) : 0;
    }

    my $checkbin = '';
    my @LOC      = ( '/usr/local/sbin/named-checkzone', '/usr/sbin/named-checkzone', '/usr/bin/named-checkzone' );
    foreach my $loc (@LOC) {
        if ( -x $loc ) {
            $checkbin = $loc;
        }
    }

    if ( !$checkbin ) {
        Cpanel::Logger::cplog( 'named-checkzone not located on system. Check your Bind installation.', 'warn', __PACKAGE__, 1 );
        return wantarray ? ( 1, '' ) : 1;
    }
    else {
        my $output = Cpanel::SafeRun::Errors::saferunallerrors( $checkbin, $zone, $zonefile );
        $output = '' if !defined $output;
        chomp $output;
        if ( $output && $output !~ m/^OK$/m ) {
            return wantarray ? ( 0, $output ) : 0;
        }
        else {
            return wantarray ? ( 1, $output ) : 1;
        }
    }
}

sub removezone {
    my ( $domain, $zonedir, $chrootdir ) = @_;
    my $resultscount = 0;
    my @removed;
    my @to_remove;
    push @to_remove, $zonedir . '/cache/' . $domain . '.db';
    push @to_remove, $zonedir . '/parse_cache/' . $domain . '.db';
    push @to_remove, $zonedir . '/ns_parse_cache/' . $domain . '.db';
    push @to_remove, $zonedir . '/' . $domain . '.db';
    push @to_remove, $zonedir . '/' . $domain;

    if ($chrootdir) {
        push @to_remove, map { $chrootdir . $_ } @to_remove;
    }

    foreach my $file (@to_remove) {
        if ( Cpanel::Autowarn::unlink($file) ) {
            push @removed, $file;
            $resultscount++;
        }
    }
    return wantarray ? ( $resultscount, \@removed ) : $resultscount;
}

1;
