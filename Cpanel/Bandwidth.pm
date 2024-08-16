package Cpanel::Bandwidth;

# cpanel - Cpanel/Bandwidth.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Time::Local ();

use Cpanel::AdminBin           ();
use Cpanel::ArrayFunc          ();
use Cpanel::BandwidthDB        ();
use Cpanel::BandwidthDB::State ();
use Cpanel::DateUtils          ();
use Cpanel::Encoder::Tiny      ();
use Cpanel::Encoder::URI       ();
use Cpanel::Locale             ();
use Cpanel::Stats              ();

our $VERSION = '1.2';

sub Bandwidth_init {
    return 1;
}

# domain - the domain where we add bandwidth
# bytes - the number of bytes to add
sub api2_addhttpbandwidth {
    my (%opts) = @_;
    return { 'result' => 0, 'reason' => 'No bytes specified.' } unless $opts{'bytes'};

    # Limit the bandwidth input numbers to between 1 and 2**64. If you need more, make multiple calls.
    return { 'result' => 0, 'reason' => 'Invalid bytes specified.' }
      unless int( $opts{'bytes'} ) > 0 && int( $opts{'bytes'} ) <= 2**64;
    return { 'result' => 0, 'reason' => 'No domain specified.' } unless $opts{'domain'};

    my $fbytes = sprintf '%-20.f', int $opts{'bytes'};
    $fbytes =~ tr/ //d;
    my $msg = Cpanel::AdminBin::adminrun( 'bandwidth', 'ADDHTTP', $opts{'domain'}, $fbytes );

    if ( !$msg ) {
        return { 'result' => 0, 'reason' => 'Unable to execute admin binary' };
    }
    if ( $msg =~ /^ERROR:\s*(.*)/ ) {
        return { 'result' => 0, 'reason' => $1 };
    }
    elsif ( $msg =~ /^STATUS:\s*/ ) {
        return { 'result' => 1, 'reason' => 'Bandwidth added for processing.' };
    }
    return { 'result' => 0, 'reason' => $msg };
}

#NOTE: This expects a 0-indexed month number.
sub within_last_thirty_days {
    my ( $mon, $day, $year ) = @_;
    my $now  = time;
    my $then = Time::Local::timelocal_modern( 0, 0, 0, $day, $mon - 1, $year );

    return $then < $now && $now - ( 86400 * 30 ) <= $then;
}

sub _strip_year_month_from_hash_keys {
    my ($hash_r) = @_;

    $hash_r->{s<.*-0?><>r} = delete $hash_r->{$_} for keys %$hash_r;

    return;
}

sub Bandwidth_displaybw {    ## no critic qw(Subroutines::ProhibitManyArgs)
    my ( $domain, $target, $tmonth, $tyear, $subd, $timezone, $protocol ) = @_;

    local $ENV{'TZ'} = $timezone if $timezone;

    $tmonth = Cpanel::DateUtils::month_num($tmonth);

    my $bwdb = Cpanel::BandwidthDB::get_reader_for_user();
    $protocol ||= 'http';         #Protocol is an optional parameter (to support older functionality)
    $protocol = lc($protocol);    #Protocols are supposed to be listed in lowercase, this enforces it.
    my $protocol_date_bytes_hr = $bwdb->get_bytes_totals_as_hash(
        ( ( defined($domain) && $domain ne '' ) ? ( 'domains' => [$domain] ) : () ),
        grouping => [ 'protocol', 'year_month_day' ],
        start    => "$tyear-$tmonth",
        end      => "$tyear-$tmonth",
    );
    my %BW = %$protocol_date_bytes_hr;

    _strip_year_month_from_hash_keys($_) for values %BW;

    my $day;
    my $tdnum                      = 1;
    my @all_enabled_protocols      = Cpanel::BandwidthDB::State::get_enabled_protocols();
    my %TOTALS                     = map  { $_ => 0 } @all_enabled_protocols;
    my @http_enabled_protocols     = grep { $_ eq $protocol } @all_enabled_protocols;
    my @non_http_enabled_protocols = grep { $_ ne $protocol } @all_enabled_protocols;
    my @protocol_list              = ( @http_enabled_protocols, ( $subd ? () : @non_http_enabled_protocols ) );

    my $html_safe_domain = Cpanel::Encoder::Tiny::safe_html_encode_str($domain);
    my $html_safe_tmonth = Cpanel::Encoder::Tiny::safe_html_encode_str($tmonth);
    my $html_safe_tyear  = Cpanel::Encoder::Tiny::safe_html_encode_str($tyear);
    my $uri_safe_domain  = Cpanel::Encoder::URI::uri_encode_str($domain);
    my $uri_safe_tmonth  = Cpanel::Encoder::URI::uri_encode_str($tmonth);
    my $uri_safe_tyear   = Cpanel::Encoder::URI::uri_encode_str($tyear);
    my $uri_safe_subd    = Cpanel::Encoder::URI::uri_encode_str($subd);
    my $uri_safe_target  = Cpanel::Encoder::URI::uri_encode_str($target);

    my $locale = Cpanel::Locale->get_handle();

    for ( $day = 1; $day <= Cpanel::Stats::getlastday( $tmonth, $tyear ); $day++ ) {
        my $all = Cpanel::ArrayFunc::sum( map { $_->{$day} } values %BW );
        $TOTALS{'all'} += $all;
        for my $prot (@protocol_list) {    #Go through each available protocol.
            if ( defined $BW{$prot}{$day} ) {    #Verify we have data for that protocol on that day.
                $TOTALS{$prot} += $BW{$prot}{$day};    #Add it to the total shown in the summary.
            }

        }

        print qq{<tr><td align="center" class="bwtdh$tdnum">};

        my $day_numf = $locale->numf($day);

        if ( within_last_thirty_days( $tmonth, $day, $tyear ) ) {
            print qq{<b><a href="bwday.html?month=$uri_safe_tmonth&year=$uri_safe_tyear&domain=$uri_safe_domain&target=$uri_safe_target&subd=$uri_safe_subd&day=$day">$day_numf</a>} .    #
              qq{</b></td><td class="bwtd$tdnum">\n};
        }
        else {
            print qq{<b>$day_numf</b></td><td class="bwtd$tdnum">\n};
        }

        print $locale->format_bytes($all) . "</td>";
        printf( qq[<td class="bwtd$tdnum">%s</td>] x ( scalar @protocol_list ), map { $locale->format_bytes( $BW{$_}{$day} ) } @protocol_list );
        $tdnum++;
        if ( $tdnum > 2 ) {
            $tdnum = 1;
        }
        print "</tr>\n\n";
    }

    printf(
        qq{<tr><td class="bwtdh$tdnum"><b>%s</b></td>},
        $locale->maketext('Total'),
    );

    printf( qq[<td class="bwtd$tdnum">%s</td>] x ( ( scalar @protocol_list ) + 1 ), map { $locale->format_bytes( $TOTALS{$_} ) } ( 'all', @protocol_list ) );
    print "</tr>\n\n";
    return;
}

our %API = (
    addhttpbandwidth => {
        needs_role => 'WebServer',
        allow_demo => 1,
    }
);

sub api2 {
    my ($func) = @_;
    return { %{ $API{$func} } } if $API{$func};
    return;
}

1;
