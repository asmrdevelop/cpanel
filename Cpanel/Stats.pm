package Cpanel::Stats;

# cpanel - Cpanel/Stats.pm                         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::Imports;
use Try::Tiny;

use Cpanel                          ();
use Cpanel::AcctUtils::DomainOwner  ();
use Cpanel::AdminBin::Call          ();
use Cpanel::ArrayFunc::Uniq         ();
use Cpanel::BandwidthDB::State      ();
use Cpanel::BandwidthDB::UserCache  ();
use Cpanel::Config::userdata::Cache ();
use Cpanel::DomainLookup            ();
use Cpanel::Encoder::Tiny           ();
use Cpanel::Exception               ();
use Cpanel::LoadModule              ();
use Cpanel::Locale                  ();
use Cpanel::Logs                    ();
use Cpanel::Math                    ();
use Cpanel::Stats::AwStats          ();
use Cpanel::Time::Local             ();
use Cpanel::Validate::Boolean       ();
use Cpanel::WildcardDomain          ();
use Time::Local                     ();
use Time::Piece                     ();
use Whostmgr::TweakSettings         ();

=head1 MODULE

C<Cpanel::Stats>

=head1 DESCRIPTION

C<Cpanel::Stats> provides various API1, API2 and support methods for site statistics tools
and other log related tools. The module contains helper methods to information from statistics
products enabled in cPanel such as webalizer, awstats, and similar. It is also used to retrieve
bandwidth reports.

=head1 CONSTANTS

=head2 MAX_READ_LINES - number

The maximum number of lines at the end of a log file we will check for user specific messages. The use can select a smaller number of lines in the related calls.

=cut

use constant MAX_READ_LINES => 5000;

=head2 AVAILABLE_LOGS - arrayref of strings

Array ref of log types supported by the list_site_logs function below.

=cut

use constant AVAILABLE_LOGS => [ 'error', 'suexec' ];

use constant AVAILABLE_ENGINES => {
    'webalizer' => [ 'http', 'ftp' ],
    'analog'    => ['http']
};

use constant AVAILABLE_MONTHLY_ENGINES => { 'analog' => ['http'] };

our $VERSION = '1.7';

my $locale;

my @MoY = ( 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec' );
my @DoW = ( 'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat' );

=head1 FUNCTIONS

=cut

sub cyclestats {
    my $stat      = shift;
    my $cycle_hrs = $Cpanel::CONF{'cycle_hours'} || 24;

    if ( $stat eq 'stats' ) {
        print int($cycle_hrs);
    }
    elsif ( $stat eq 'bwstats' ) {
        print int( $cycle_hrs / 4 );
    }
    elsif ( $stat eq 'waittime' ) {
        print int( $cycle_hrs * 1.5 );
    }
    return;
}

sub countbandwidth {
    return if ( !Cpanel::hasfeature('bandwidth') );

    my $tbytes = _get_this_months_total_bw_usage();
    return Cpanel::Math::floatto( ( $tbytes / (1048576) ), 2 );
}

sub countbandwidth_bytes {
    die 'need “bandwidth” priv!' if !Cpanel::hasfeature('bandwidth');

    return scalar _get_this_months_total_bw_usage();
}

sub _make_date_key {
    my ( $month, undef, $year ) = split( m{\.}, shift(), 3 );
    $year =~ s{-\w+$}{};
    return if $year <= 1970;
    $month = sprintf( "%02d", $month );
    return "$year-$month";
}

#Returns a list of hashes: [
#   {
#       date => 'YYYY-MM',
#       bw => {
#           domain1.tld => 123,
#           domain2.tld => 456,
#           ...
#       },
#   },
#   ...
#]
#
sub api2_getmonthlydomainbandwidth {

    Cpanel::LoadModule::load_perl_module('Cpanel::BandwidthDB');
    my $bwdb = Cpanel::BandwidthDB::get_reader_for_user();

    my $date_domain_bw_hr = $bwdb->get_bytes_totals_as_hash(
        grouping => [ 'year_month', 'domain' ],
    );

    return [ map { ( date => $_, bw => $date_domain_bw_hr->{$_} ) } sort keys %$date_domain_bw_hr ];
}

sub api2_getmonthlybandwidth {

    Cpanel::LoadModule::load_perl_module('Cpanel::BandwidthDB');
    my $bwdb = Cpanel::BandwidthDB::get_reader_for_user();

    my $res_ar = $bwdb->get_bytes_totals_as_array(
        grouping => ['year_month'],
    );

    $_ = { date => $_->[0], bw => $_->[1] } for @$res_ar;

    return $res_ar;
}

=head2 get_bandwidth( %ARGS )

Retrieves a list of bandwidth records sorted by the date, the protocol and the domain.

Inputs are:

=over

=item * C<timezone> - (optional) Olson TZ timezone (e.g., C<America/Chicago>)

=back

Sorting rules are a little complex:

=over

=item - records are sorted by date with newest bandwidth records first.

=item - protocols are sorting in the following order

=over

=item 1) http

=item 2) ftp

=item 3) imap

=item 4) pop3

=item 5) smtp

=back

=item - for http traffic, the primary domain is listed first and the other domains are listed in alphabetical order.

=back

=head3 RETURNS

An arrayref of hashrefs with the following structure:

=over

=item month_start - unix timestamp

Only the month and year are significant. Ignore all other parts of the date.

=item domain

Domain the traffic belongs to. Only applicable to http traffic.

=item protocol - string

=over

=item - http

=item - ftp

=item - imap

=item - pop3

=item - smtp

=back

=item bytes - number

Bytes of bandwidth consumed for the domain/protocol for the month indicated in month_start

=back

=cut

sub get_bandwidth (%args) {

    require Cpanel::BandwidthDB;

    my @results;
    my @enabled_protocols = Cpanel::BandwidthDB::State::get_enabled_protocols();
    my $db                = Cpanel::BandwidthDB::get_reader_for_user();
    my $totals            = $db->get_bytes_totals_as_array( grouping => [ 'domain', 'protocol', 'year_month' ] );
    my $localtime         = Time::Piece->new();
    my %monthly_protocols;

    local $ENV{'TZ'} = $args{'timezone'} || $ENV{'TZ'} || do {
        require Cpanel::Timezones;
        Cpanel::Timezones::calculate_TZ_env();
    };

    require Cpanel::LinkedNode::Worker::User;
    my @remote_results = Cpanel::LinkedNode::Worker::User::call_all_workers_uapi(
        'Stats', 'get_bandwidth',
        {
            timezone => $ENV{'TZ'},
        },
    );

    for my $total (@$totals) {
        my ( $domain, $protocol, $year_month, $bytes ) = @$total;
        my $ptime = $localtime->strptime( $year_month, "%Y-%m" );
        my $epoch = $ptime ? $ptime->epoch : $year_month;

        $domain = ( $protocol eq 'http' ) ? $domain : $Cpanel::CPDATA{'DNS'};

        for my $rres (@remote_results) {
            my $data = $rres->{'result'}->data();

            for my $item (@$data) {
                next if $item->{'domain'} ne $domain;
                next if $item->{'protocol'} ne $protocol;

                # This *should* work since we send “timezone” to the remote.
                next if $item->{'month_start'} != $epoch;

                $bytes += $item->{'bytes'};
            }
        }

        push(
            @results,
            {
                'month_start' => $epoch,
                'domain'      => $domain,
                'protocol'    => $protocol,
                'bytes'       => $bytes
            }
        );

        $monthly_protocols{$epoch} = () if !exists( $monthly_protocols{$epoch} );
        push( @{ $monthly_protocols{$epoch} }, $protocol );

    }

    for my $month ( keys %monthly_protocols ) {
        for my $protocol (@enabled_protocols) {
            next if grep { $_ eq $protocol } @{ $monthly_protocols{$month} };
            push(
                @results,
                {
                    'month_start' => $month,
                    'domain'      => $Cpanel::CPDATA{'DNS'},
                    'protocol'    => $protocol,
                    'bytes'       => 0
                }
            );
        }
    }

    my %sort_protocol = (
        http => 5,
        ftp  => 4,
        imap => 3,
        pop3 => 2,
        smtp => 1,
    );

    # Sort by month (most recent first),
    # then by protocol, but with HTTP first
    # then by domain, but with the primary domain first
    # For a given month we get:
    #
    #   HTTP - primary domain
    #   HTTP - a domain
    #   ...
    #   HTTP - z domain
    #   FTP
    #   IMAP
    #   POP3
    #   SMTP
    #
    @results =
      sort { $b->{month_start} <=> $a->{month_start} || ( $sort_protocol{ $b->{protocol} } <=> $sort_protocol{ $a->{protocol} } ) || ( $b->{domain} eq $Cpanel::CPDATA{DNS} ? 1 : $a->{domain} cmp $b->{domain} ) } @results;

    return \@results;

}

sub showbandwidth {
    if ( !main::hasfeature("bandwidth") ) { return (); }

    my $mon;
    my (%HASSEEN);
    my %DEADDOMAINS;
    if ( ref $Cpanel::CPDATA{'DEADDOMAINS'} eq 'ARRAY' ) {
        %DEADDOMAINS = map { $_ => 1 } @{ $Cpanel::CPDATA{'DEADDOMAINS'} };
    }

    Cpanel::LoadModule::load_perl_module('Cpanel::BandwidthDB');
    my $bwdb = Cpanel::BandwidthDB::get_reader_for_user();

    my @all_enabled_protocols      = Cpanel::BandwidthDB::State::get_enabled_protocols();
    my @http_enabled_protocols     = grep { $_ eq 'http' } @all_enabled_protocols;
    my $http_is_enabled            = @http_enabled_protocols ? 1 : 0;
    my @non_http_enabled_protocols = grep { $_ ne 'http' } @all_enabled_protocols;

    my $non_http_bw_hr = $bwdb->get_bytes_totals_as_hash(
        grouping  => [ 'protocol', 'year_month' ],
        protocols => \@non_http_enabled_protocols,
    );

    my $user_main_domain = $Cpanel::CPDATA{'DNS'};

    my $bbw_hr = $bwdb->get_bytes_totals_as_hash(
        grouping  => [ 'domain', 'year_month' ],
        protocols => ['http'],
    );

    my @dates = sort( Cpanel::ArrayFunc::Uniq::uniq(
            ( map { keys %{ $non_http_bw_hr->{$_} } } keys %$non_http_bw_hr ),
            ( map { keys %{ $bbw_hr->{$_} } } keys %$bbw_hr ),
    ) );

    my $locale = Cpanel::Locale->get_handle();

    Cpanel::LoadModule::load_perl_module('Cpanel::CLDR::DateTime');
    my @months = Cpanel::CLDR::DateTime::month_stand_alone_wide();

    my $deleted_text      = $locale->maketext('deleted');
    my $cp_security_token = $ENV{'cp_security_token'} || '';

    Cpanel::LoadModule::load_perl_module('Cpanel::ArrayFunc');
    my $id = 0;
    foreach my $date ( reverse @dates ) {
        $id++;
        my (@BDATA);
        my $dcount = -1;
        my $domain = $Cpanel::CPDATA{'DNS'};
        my ( $year, $monnum ) = split( /-/, $date );
        my $bytes = $bbw_hr->{$domain}{$date};
        $mon = $MoY[ ( int($monnum) - 1 ) ];
        my $mon_disp = $months[ int($monnum) - 1 ];
        my $xfer     = $locale->format_bytes($bytes);

        if ( !$HASSEEN{"$mon $year"} ) {
            main::brickstart("$mon_disp $year");
            print "<table width=100%><tr><td align=center>" . "<table cellpadding=2 cellspacing=0 width=100%>";
        }
        $HASSEEN{"$mon $year"} = 1;
        if ($http_is_enabled) {
            $dcount++;
            push( @BDATA, $bytes );
            print "<tr><td class=bwtableb><img src=\"$cp_security_token/backend/piegraph.cgi?color=${dcount}\" align=absmiddle>
         <a href=\"detailsubbw.html?mon=$mon&year=$year&domain=$domain&target=$domain\">HTTP — $domain" . ( $DEADDOMAINS{$domain} ? " ($deleted_text)" : '' ) . "</b></a></td><td width=30% class=bwtableb style='text-align:right;' align=right>${xfer}</td></tr>\n";

            foreach $domain ( sort keys %{$bbw_hr} ) {
                next if $domain eq 'UNKNOWN';
                next if ( $domain eq "$Cpanel::CPDATA{'DNS'}" );

                my $bytes = $bbw_hr->{$domain}{$date};
                $dcount++;
                push( @BDATA, $bytes );

                ( $year, $monnum ) = split( /-/, $date );
                $mon = $MoY[ ( int($monnum) - 1 ) ];
                my $mon_disp = $months[ int($monnum) - 1 ];

                my $xfer = $locale->format_bytes($bytes);
                print "<tr><td class=bwtableb><img src=\"$cp_security_token/backend/piegraph.cgi?color=${dcount}\" align=absmiddle>
         <a href=\"detailsubbw.html?mon=$mon&year=$year&domain=$domain&target=$domain\">HTTP — $domain" . ( $DEADDOMAINS{$domain} ? " ($deleted_text)" : '' ) . "</a></td><td width=30% class=bwtableb style='text-align:right;' align=right>${xfer}</td></tr>\n";
            }
        }

        foreach my $key (@non_http_enabled_protocols) {
            $dcount++;
            my $nicekey    = uc $key;
            my $totalbytes = $non_http_bw_hr->{$key}{$date};
            push( @BDATA, $totalbytes );
            my $keyxfer = $locale->format_bytes($totalbytes);

            print "<tr><td class=bwtableb style='text-align: left;' align=left><img src=\"$cp_security_token/backend/piegraph.cgi?color=${dcount}\" align=absmiddle><a href=\"detailbw.html?mon=$mon&year=$year&domain=$domain&target=$Cpanel::user\"> $nicekey</a></td><td class=bwtableb align=right style='text-align:right;'>${keyxfer}</td></tr>\n";
        }

        my $monnum_with_0 = sprintf( '%02d', $monnum );

        my $totalbytes = Cpanel::ArrayFunc::sum(
            ( map { $_->{"$year-$monnum_with_0"} } values %{$bbw_hr} ),
            ( map { $_->{"$year-$monnum_with_0"} } values %{$non_http_bw_hr} ),
        );
        $xfer = $locale->format_bytes($totalbytes);

        my $total_phrase = $locale->maketext('Total (all services)');

        print "<tr><td class=bwtable style='text-align: left;' align=left><div style='width: 22px;float:left;'>&nbsp;</div><B><a href=\"detailbw.html?mon=$mon&year=$year&domain=$domain&target=$Cpanel::user\">$total_phrase</a></B></td><td class=bwtable align=right style='text-align:right;'>${xfer}</td></tr>\n" . "</table>" . "</td>";

        my $fdata = '';
        my $i     = 0;
        foreach my $bdata (@BDATA) {
            $i++;
            $bdata ||= 0;
            $fdata .= "${i}=${bdata}&";
        }
        if ( $id == 1 ) {
            print "<td width=25% align=center><a href=\"detailbw.html?mon=$mon&year=$year&domain=$domain&target=$Cpanel::user\"><img border=\"0\" src=\"$cp_security_token/backend/piegraph.cgi?${fdata}action=pie\"></a></td>";
        }
        else {
            print "<td width=25% align=center><a href=\"detailbw.html?mon=$mon&year=$year&domain=$domain&target=$Cpanel::user\"><img
         name=pie${id} src=\"/hoverToShow.png\"
         onMouseOver=\"document.pie${id}.src='$cp_security_token/backend/piegraph.cgi?${fdata}action=pie'\" border=\"0\"></a></td>";
        }
        print "</td></tr></table>";
        main::brickend();
        print "<br>";
    }
    return;
}

sub getlastday {
    my ( $mon, $year ) = @_;
    if ( !$mon || !$year ) {
        ( undef, undef, undef, undef, $mon, $year, undef, undef, undef ) = localtime( time() );
        $mon++;
        $year += 1900;
    }
    if ( $mon == 2 ) {
        if ( $year % 4 == 0 ) {
            if ( ( !( $year % 100 == 0 ) ) || ( $year % 400 == 0 ) ) {
                return 29;
            }
        }
        return 28;
    }
    elsif ( $mon == 4 || $mon == 6 || $mon == 9 || $mon == 11 ) {
        return 30;
    }
    elsif ( $mon == 12 || $mon == 10 || $mon == 8 || $mon == 7 || $mon == 5 || $mon == 3 || $mon == 1 ) {
        return 31;
    }
}

sub analoglist {
    my ( $ddomain, $sopts ) = @_;
    my $sdir = $sopts ? '/ssl' : '';

    my $safe_ddomain = Cpanel::WildcardDomain::encode_wildcard_domain($ddomain);
    if ( !$sopts && $ddomain eq $Cpanel::CPDATA{'DNS'} ) {
        $safe_ddomain = '';
    }
    else {
        $safe_ddomain = '/' . $safe_ddomain;
    }
    my $html_safe_ddomain = Cpanel::Encoder::Tiny::safe_html_encode_str($safe_ddomain);

    my $this_year  = getyear();
    my $this_month = getmonth();
    my @dates      = ( $this_month + 1 ) .. 12;
    push @dates, 1 .. $this_month;
    my $year_space = 0;
    foreach my $month ( reverse @dates ) {
        next if !-f $Cpanel::homedir . '/tmp/analog' . $sdir . $safe_ddomain . '/' . $month . '.html';
        my $year = $this_year;
        if ( $month > $this_month ) {
            $year--;
            print "<br />\n" if !$year_space;
            $year_space = 1;
        }
        print qq{<a href="$ENV{'cp_security_token'}/tmp/} . Cpanel::Encoder::Tiny::safe_html_encode_str($Cpanel::user) . qq{/analog${sdir}${html_safe_ddomain}/${month}.html">$MoY[$month - 1] $year</a><br />\n};
    }
    return;
}

sub analog {
    my $domain = shift;
    Cpanel::LoadModule::load_perl_module('Cpanel::Logs::Find');
    my $accesslog = Cpanel::Logs::Find::find_wwwaccesslog($domain);

    if ( !$accesslog ) {
        return 'nolog.html';
    }

    return "/tmp/$Cpanel::user/analog/" . getmonth() . ".html";
}

sub errlog {
    my ($domain) = @_;
    if ( !main::hasfeature("errlog") ) { return (); }
    require Cpanel::Validate::Domain::Tiny;
    if ( !Cpanel::Validate::Domain::Tiny::validdomainname($domain) ) {
        return 'nolog.html';
    }

    my ( @STATS, $lcount, $size );
    Cpanel::LoadModule::load_perl_module('Cpanel::Logs::Find');
    my ($errlog) = Cpanel::Logs::Find::find_wwwerrorlog($domain);
    Cpanel::LoadModule::load_perl_module('Cpanel::ConfigFiles::Apache');
    my ($suexeclog) = Cpanel::ConfigFiles::Apache::apache_paths_facade()->dir_logs() . '/suexec_log';

    if ( !$errlog ) {
        return 'nolog.html';
    }

    ( undef, undef, undef, undef, undef, undef, undef, $size, undef, undef, undef, undef, undef ) = stat($errlog);

    $size = ( $size - 2097152 );
    my ($homeregex) = $Cpanel::homedir . "/";
    $homeregex =~ s/\/home\d*\//\/home\\d*\//g;

    if ( open( my $err_fh, "<", $errlog ) ) {
        if ( $size > 0 ) { seek( $err_fh, $size, 0 ); }
        while (<$err_fh>) {
            chomp($_);
            if (/${homeregex}/) {
                $lcount++;
                my ($ent) = cleanfield($_);
                push( @STATS, $ent );
            }
        }
        close($err_fh);
    }

    while ( $#STATS > 300 ) {
        shift(@STATS);
    }

    if ( -e $suexeclog ) {
        my $susize;
        ( undef, undef, undef, undef, undef, undef, undef, $susize, undef, undef, undef, undef, undef ) = stat($suexeclog);

        $susize = ( $susize - 2097152 );
        if ( open( my $serr_fh, "<", "$suexeclog" ) ) {
            if ( $susize > 0 ) { seek( $serr_fh, $susize, 0 ); }
            while (<$serr_fh>) {
                chomp($_);
                if ( /error/ && ( /${homeregex}/ || /\($Cpanel::user\)/ ) ) {
                    $lcount++;
                    my ($ent) = cleanfield($_);
                    push( @STATS, $ent );
                }
            }
        }
    }

    while ( $#STATS > 600 ) {
        shift(@STATS);
    }

    return reverse(@STATS);
}

sub webalizer {
    my ($domain) = @_;
    Cpanel::LoadModule::load_perl_module('Cpanel::Logs::Find');
    my ($accesslog) = Cpanel::Logs::Find::find_wwwaccesslog( Cpanel::WildcardDomain::encode_wildcard_domain($domain) );

    if ( $accesslog eq "" && !-e "$Cpanel::homedir/tmp/webalizer/index.html" ) {
        return "nolog.html";
    }

    if ( !-e "$Cpanel::homedir/tmp/webalizer/index.html" ) {
        mkdir( "$Cpanel::homedir/tmp",           0700 );
        mkdir( "$Cpanel::homedir/tmp/webalizer", 0700 );

        if ( open( my $ih, ">", "$Cpanel::homedir/tmp/webalizer/index.html" ) ) {
            say {$ih} "Webalizer stats have not yet been generated!";
        }
    }
    return "$ENV{'cp_security_token'}/tmp/$Cpanel::user/webalizer/index.html";
}

=head2 list_webalizer_http()

Get information about location and status of Webalizer HTTP based logs.

=head3 ARGUMENTS

none

=head3 RETURNS

A list of hashrefs for each domain stats are available for. Each hashref contains:

=over

=item ssl - boolean 0 or 1 - whether this is for an SSL host.

=item path - string - URI encoded path to the stats page.

=item domain - the domain the statistics link is related to.

=item all_domains - boolean - 1 when the statistics link is for all the users domains.

=back

=head3 THROWS

=over 1

=item when the webalizer feature is not enabled

=back

=cut

sub list_webalizer_http {
    my @result;

    die Cpanel::Exception::create( 'FeatureNotEnabled', [ feature_name => 'webalizer' ] ) if !Cpanel::hasfeature('webalizer');

    my @data = _fullWebalizerList();

    require Cpanel::Encoder::URI;

    for my $item (@data) {

        my $path = sprintf( "/tmp/%s/webalizer/", $Cpanel::user );
        $path .= sprintf( "%s/", $item->{'dir'} ) if ( $item->{'dir'} );
        $path .= "index.html";
        $path = Cpanel::Encoder::URI::uri_encode_dirstr($path);

        push @result, {
            'path'        => $path,
            'domain'      => $item->{'domain'},
            'ssl'         => $item->{'ssl'},
            'all_domains' => 0
        };

    }

    return @result;
}

=head2 list_analog_by_domain_group_by_month(DOMAIN, SSL)

List up to the last 12 access statistics report urls for a given domain.

Any reports that are missing are not returned.

=head3 ARGUMENTS

=over

=item DOMAIN - string

The users domain you want monthly reports from.

=item SSL - Boolean

When 1 returns ssl access reports. When 0 returns non-ssl access reports. Defaults to 1.

=back

=head3 RETURNS

Array ref where each element of the array is a hash ref with the following structure:

=over

=item date - Unix timestamp

The month and year encoded as a timestamp. Note: Other fields in the date are fixed so
for Aug 2019, the date is set as 2019-08-01 00:00:00.

=item url - string

Session relative URL used to access the months statistics reports.

=back

=head3 THROWS

=over

=item When the user does not have permission to use this feature

=item When the engine parameter is not provided.

=item When the engine requested is not valid for this API.

=item When the domain requested is not owned by the current cPanel user.

=item When the ssl parameter is not a valid Boolean.

=back

=cut

sub list_analog_by_domain_group_by_month {
    my ( $domain, $ssl ) = @_;

    die Cpanel::Exception::create( 'FeatureNotEnabled', [ feature_name => 'analog' ] ) if !Cpanel::hasfeature('analog');

    my $homedir = $Cpanel::homedir // Cpanel::PwCache::gethomedir($>);

    $domain = Cpanel::WildcardDomain::encode_wildcard_domain($domain);
    if ( !$ssl && $domain eq $Cpanel::CPDATA{'DNS'} ) {
        $domain = '';
    }

    my $html_safe_domain = Cpanel::Encoder::Tiny::safe_html_encode_str($domain);
    my $html_safe_user   = Cpanel::Encoder::Tiny::safe_html_encode_str($Cpanel::user);

    # Get the current month and year
    my ( undef, undef, undef, undef, $month, $year, undef, undef, undef, undef ) = localtime( _now() );
    $month++;
    $year += 1900;

    my $count = 0;
    my @data;

    # We want to check up to 12 months.
    # So starting in August 2019 we will look
    # for reports in the following window.
    #
    #   8 7 6 5 4 3 2 1 12 11 10 9
    #  ----- 2019 ---- | -- 2018 --
    #
    while ( $count < 12 ) {

        # Calculate the storage directory
        #
        # - For primary domain ssl in January:
        #   /home/cpuser/tmp/analog/ssl/1.html
        # - For primary domain non-ssl in January:
        #   /home/cpuser/tmp/analog/1.html
        # - For other domains ssl in January:
        #   /home/cpuser/tmp/analog/ssl/other.tld/1.html
        # - For other domains non-ssl in January:
        #   /home/cpuser/tmp/analog/other.tld/1.html
        my $path = $Cpanel::homedir . '/tmp/analog/' . ( $ssl ? 'ssl/' : '' ) . ( $domain ? "$domain/" : '' ) . $month . '.html';
        if ( !-f $path ) {
            $count++;
            ( $month, $year ) = _previous_month_and_year( $month, $year );
            next;
        }

        # Calculate the url
        #
        # - For primary domain ssl in January:
        #   tmp/cpuser/analog/ssl/1.html
        # - For primary domain non-ssl in January:
        #   tmp/cpuser/analog/1.html
        # - For other domains ssl in January:
        #   tmp/cpuser/analog/ssl/other.tld/1.html
        # - For other domains non-ssl in January:
        #   tmp/cpuser/analog/other.tld/1.html
        my $url = qq{tmp/${html_safe_user}/analog/} . ( $ssl ? 'ssl/' : '' ) . ( $domain ? "$html_safe_domain/" : '' ) . qq{${month}.html};

        my $date_string = $year . '-' . sprintf( '%02d', $month ) . '-01T00:00:00Z';
        my $timestamp   = Time::Local::timelocal_modern( 0, 0, 0, 1, $month - 1, $year );

        push @data, {
            url  => $url,
            date => $timestamp,
        };
        $count++;
        ( $month, $year ) = _previous_month_and_year( $month, $year );
    }

    return \@data;
}

# For unit tests.
sub _now () {
    return time;
}

sub _previous_month_and_year {
    my ( $month, $year ) = @_;
    $month--;
    if ( $month == 0 ) {
        $year--;
        $month = 12;
    }
    return ( $month, $year );
}

=head2 list_analog_http()

Get information about location and status of Analog HTTP based logs.

=head3 ARGUMENTS

none

=head3 RETURNS

A list of hashrefs for each domain stats are available for. Each hashref contains:

=over

=item ssl - boolean 0 or 1 - whether this is for an SSL host.

=item path - string - URI encoded path to the stats page.

=item domain - the domain the statistics link is related to.

=item all_domains - boolean - 1 when the statistics link is for all the users domains.

=back

=head3 THROWS

=over 1

=item when the analog feature is not enabled

=back

=cut

sub list_analog_http {
    my @result;

    die Cpanel::Exception::create( 'FeatureNotEnabled', [ feature_name => 'analog' ] ) if !Cpanel::hasfeature('analog');

    my @data = _fullAnalogList();

    require Cpanel::Encoder::URI;

    for my $item (@data) {

        my $path = sprintf(
            "analog.html?domain=%s&ssl=%u",
            Cpanel::Encoder::URI::uri_encode_str( $item->{'domain'} ),
            Cpanel::Encoder::URI::uri_encode_str( $item->{'ssl'} )
        );

        push @result, {
            'path'        => $path,
            'domain'      => $item->{'domain'},
            'ssl'         => $item->{'ssl'},
            'all_domains' => 0
        };

    }

    return @result;
}

=head2 list_webalizer_ftp()

Get information about location and status of Webalizer FTP based logs.

=head3 ARGUMENTS

none

=head3 RETURNS

A list containing a hashref if stats are available for the user. Empty list otherwise.
This format is compatable with list_webalizer_http. The hashref contains:

=over

=item ssl - boolean 0 or 1 - whether this is for an SSL host.

=item path - string - URI encoded path to the stats page.

=item all_domains - boolean - 1 when the statistics link is for all the users domains.

=back

=head3 THROWS

=over 1

=item when the webalizer feature is not enabled

=back

=cut

sub list_webalizer_ftp {
    my @result;

    die Cpanel::Exception::create( 'FeatureNotEnabled', [ feature_name => 'webalizer' ] ) if !Cpanel::hasfeature('webalizer');

    require Cpanel::PwCache;
    require Cpanel::Encoder::URI;

    my $homedir = $Cpanel::homedir // Cpanel::PwCache::gethomedir($>);

    if ( -e "${homedir}/tmp/webalizerftp/index.html" ) {

        my $path = Cpanel::Encoder::URI::uri_encode_dirstr("/tmp/${Cpanel::user}/webalizerftp/index.html");

        push @result, {
            'path'        => $path,
            'domain'      => undef,
            'all_domains' => 1,
            'ssl'         => 0,
        };
    }

    return @result;
}

=head2 list_sites_stats($engine, $traffic)

Get information about location and status of supported stats engines. It is a convenience method
for calling the various list_ methods for supported stats engines and traffic types.

=head3 ARGUMENTS

=over

=item engine - string, must be one of the keys in AVAILABLE_ENGINES constant.

=item traffic - string, must be one of the items in AVAILABLE_ENGINES->{$engine} constant.

=back

=head3 RETURNS

A list of hashrefs for each domain stats are available for. Each hashref contains:

=over

=item ssl - boolean 0 or 1 - whether this is for an SSL host.

=item path - string - URI encoded path to the stats page.

=item all_domains - boolean - 1 when the statistics link is for all the users domains.

=back

=head3 THROWS

=over

=item When the engine parameter is not one of the available engines.

=item When the traffic parameter is not in an engines list of available traffic types.

=item When a suitable method for handling these types is not yet implemented.

=back

=cut

sub list_sites_stats {
    my ( $engine, $traffic ) = @_;

    my $engine_valid = defined($engine) && exists( AVAILABLE_ENGINES->{$engine} );
    my $traffic_valid =
      ( $engine_valid && defined($traffic) )
      ? grep { $traffic eq $_ } @{ AVAILABLE_ENGINES->{$engine} }
      : 0;
    my $method = undef;

    if ( $engine_valid && $traffic_valid ) {
        if ( my $method = Cpanel::Stats->can("list_${engine}_${traffic}") ) {
            return $Cpanel::Stats->$method;
        }
    }

    die Cpanel::Exception::create(
        'InvalidParameter',
        "Engine “[_1]” is not valid. Enter one of the following: [list_or_quoted,_2].",
        [ $engine, [ keys %{ AVAILABLE_ENGINES() } ] ]
    ) if !$engine_valid;

    die Cpanel::Exception::create(
        'InvalidParameter',
        "Traffic parameter “[_1]” is not valid for the engine “[_2]”. Enter one of the following: [list_or_quoted,_3].",
        [ $traffic, $engine, AVAILABLE_ENGINES->{$engine} ]
    ) if !$traffic_valid;

    die Cpanel::Exception::create(
        'Unsupported',
        "Traffic parameter “[_1]” is not supported for the engine “[_2]”.",
        [ $traffic, $engine ]
    );
}

=head2 list_stats_by_domain_group_by_month(ENGINE, DOMAIN, SSL)

List the domains statistics links for a requested engine.

This provides up to 12 months of reports. Any months where reports were
not generated will be missing from the returned list.

=head3 ARGUMENTS

=over

=item ENGINE - string

The statistics reporting engine. Currently we only support: analog.

=item DOMAIN - string

The users domain you want monthly reports from.

=item SSL - Boolean

When 1 returns ssl access reports. When 0 returns non-ssl access reports. Defaults to 1.

=back

=head3 RETURNS

Array ref where each element of the array is a hash ref with the following structure:

=over

=item date - Unix timestamp

The month and year encoded as a timestamp. Note: Other fields in the date are fixed so
for Aug 2019, the date is set as 2019-08-01 00:00:00.

=item url - string

Session relative URL used to access the months statistics reports.

=back

=head3 THROWS

=over

=item When the user does not have permission to use this feature

=item When the engine parameter is not provided.

=item When the engine requested is not valid for this API.

=item When the domain requested is not owned by the current cPanel user.

=item When the ssl parameter is not a valid Boolean.

=back

=cut

sub list_stats_by_domain_group_by_month {
    my ( $engine, $domain, $ssl ) = @_;

    die Cpanel::Exception::create(
        'InvalidParameter',
        "Engine “[_1]” is not valid. Enter one of the following: [list_or_quoted,_2].",
        [ $engine, [ keys %{ AVAILABLE_MONTHLY_ENGINES() } ] ]
    ) if !defined($engine) || !exists( AVAILABLE_MONTHLY_ENGINES->{$engine} );

    die Cpanel::Exception::create(
        'InvalidParameter',
        "Domain “[_1]” is not valid.",
        [$domain],
    ) if !Cpanel::AcctUtils::DomainOwner::is_domain_owned_by( $domain, $Cpanel::user );

    Cpanel::Validate::Boolean::validate_or_die( $ssl, 'ssl' );
    if ( my $method = Cpanel::Stats->can("list_${engine}_by_domain_group_by_month") ) {
        return &$method( $domain, $ssl );
    }

    return;
}

sub webalizerftp {
    my ($domain) = @_;
    Cpanel::LoadModule::load_perl_module('Cpanel::Logs::Find');
    my ($ftplog) = Cpanel::Logs::Find::find_ftplog( Cpanel::WildcardDomain::encode_wildcard_domain($domain) );

    if ( $ftplog eq "" && !-e "$Cpanel::homedir/tmp/webalizerftp/index.html" ) {
        return "nolog.html";
    }

    if ( !-e "$Cpanel::homedir/tmp/webalizerftp/index.html" ) {
        mkdir( "$Cpanel::homedir/tmp",              0700 );
        mkdir( "$Cpanel::homedir/tmp/webalizerftp", 0700 );

        if ( open( my $ih, ">", "$Cpanel::homedir/tmp/webalizerftp/index.html" ) ) {
            say {$ih} "Webalizer ftp stats have not yet been generated!";
        }
    }
    return "$ENV{'cp_security_token'}/tmp/$Cpanel::user/webalizerftp/index.html";
}

sub api2_lastapachehits {    ## no critic qw(Subroutines::ProhibitExcessComplexity) - requires refactor
    my %OPTS = @_;

    require HTTP::Date;

    my ( $domain, $numlines, $ssl ) = @OPTS{qw(domain numlines ssl)};
    my ( $date, $host, $tz, $url, $http, $method, $timestamp, $code, $size, $referer, $agent, @RSD );

    require Cpanel::Validate::Domain::Tiny;
    if ( !Cpanel::Validate::Domain::Tiny::validdomainname($domain) ) {
        $Cpanel::CPERROR{'stats'} = "Invalid domain: $domain";
        return;
    }

    $numlines = int( $numlines // 0 );    #fix security hole
    if ( !$numlines || $numlines > 1000 ) { $numlines = 1000; }

    Cpanel::LoadModule::load_perl_module('Cpanel::Logs::Find');
    my $safe_domain = Cpanel::WildcardDomain::encode_wildcard_domain($domain);
    my $accesslog   = $ssl ? Cpanel::Logs::Find::find_sslaccesslog($safe_domain) : Cpanel::Logs::Find::find_wwwaccesslog($safe_domain);

    my $is_nginx = Cpanel::Logs::path_is_nginx_domain_log($accesslog);

    # If it is nginx, we still need to process the apache log too for any direct hits
    my $apache_accesslog;
    if ($is_nginx) {

        # Taken from Cpanel::Logd

        # UGMO 1 global internal: NGINX log can exist at this point so we need to drop it for this pass:
        local @Cpanel::Logs::Find::_default_log_locations = @Cpanel::Logs::Find::_default_log_locations;
        shift @Cpanel::Logs::Find::_default_log_locations;

        # UGMO 2 global internal: the cached _default_log_locations is also cached based on mtime so we need to drop it here too
        local @Cpanel::Logs::Find::_log_locations = @Cpanel::Logs::Find::_log_locations;
        shift @Cpanel::Logs::Find::_log_locations;

        $apache_accesslog = $ssl ? Cpanel::Logs::Find::find_sslaccesslog($safe_domain) : Cpanel::Logs::Find::find_wwwaccesslog($safe_domain);
    }

    my $first_col_is_domain_and_port = $is_nginx && !Whostmgr::TweakSettings::get_value( Main => "enable_piped_logs" ) ? 80 : 0;
    if ( $ssl && $first_col_is_domain_and_port ) {
        $first_col_is_domain_and_port = 443;
    }

    # in case they are running NGINX on funny ports
    if ($first_col_is_domain_and_port) {
        my $unstd_port_file = $ssl ? "apache_ssl_port.initial" : "apache_port.initial";

        if ( open my $fh, "<", "/etc/nginx/ea-nginx/meta/$unstd_port_file" ) {
            my $setting = <$fh>;
            close $fh;

            my ( undef, $port ) = split( /:/, $setting );
            if ( length($port) ) {
                chomp $port;    # shouldn’t be necessary but just in case
                if ( $port =~ m/^[0-9]+$/ ) {
                    $first_col_is_domain_and_port = $port;
                }
            }
        }
    }

    #Save memory rather than reading lines into a list all at once.

    foreach my $log ( $accesslog, $apache_accesslog ) {
        last unless $log;    # if it is not nginx, then $apache_accesslog will be undefined
        if ( open( my $log_tail, '-|', "tail -$numlines $log" ) ) {
            my $line_counter = 0;
            while ( readline($log_tail) ) {
                chomp;

                if ($first_col_is_domain_and_port) {    # we are NGINX and are not currently running piped logs …
                    if (s/^\S+:([0-9]+)\s+//) {         # so detect (snd strip) the special domain:port column …
                        my $line_port = $1;
                        next if $line_port ne $first_col_is_domain_and_port;    # and ignore ones that are not the port we want
                    }
                    elsif ($ssl) {
                        logger->info("Ignoring piped log line from non-SSL access log ($_)\n\tDid you recently switch off piped logging?");
                        next;
                    }
                    else {
                        logger->info("Including piped log line from non-SSL access log ($_)\n\tDid you recently switch off piped logging?");
                    }
                }
                elsif ( $is_nginx && m/^\S+:([0-9]+)\s+/ ) {    # we are NGINX and are currently running piped logs and we see a non-piped log line …
                    my $line_port = $1;

                    # best effort, wonky ports will get overlooked but YAGNI
                    if ( $ssl && $line_port eq "443" ) {
                        logger->info("Including non-piped log line ($_)\n\tDid you recently switch on piped logging?");
                    }
                    elsif ( !$ssl && $line_port eq "80" ) {
                        logger->info("Including non-piped log line ($_)\n\tDid you recently switch on piped logging?");
                    }
                    else {
                        logger->info("Ignoring non-piped log line ($_)\n\tDid you recently switch on piped logging?");
                        next;
                    }

                    s/^\S+:([0-9]+)\s+//;    # strip off special domain:port column
                }

                ( $host, undef, undef, $date, $tz, $method, $url, $http, $code, $size, $referer, $agent ) = split( m{ }, $_, 12 );
                next if !$code;

                $date    =~ tr{[}{}d;
                $tz      =~ tr{]}{}d;
                $method  =~ tr{"}{}d;
                $http    =~ tr{"}{}d;
                $referer =~ tr{"}{}d;
                $agent   =~ tr{"}{}d;
                $timestamp = HTTP::Date::str2time( $date, $tz );

                push @RSD, {
                    'line'      => $line_counter,
                    'ip'        => $host,
                    'httpdate'  => $date,
                    'tz'        => $tz,
                    'timestamp' => $timestamp,
                    'method'    => $method,
                    'url'       => $url,
                    'protocol'  => $http,
                    'status'    => $code,
                    'size'      => ( $size =~ m{\A\s*-\s*\z} ) ? 0 : $size,

                    #spelling consistent with HTTP spec, inconsistent with DOM2
                    'referer' => ( $referer =~ m{\A\s*-\s*\z} ) ? q{} : $referer,
                    'agent'   => ( $agent   =~ m{\A\s*-\s*\z} ) ? q{} : $agent,
                };
                $line_counter++;
            }
            close $log_tail;
        }

        # The second iteration of the loop only occurs if the first iteration is for nginx
        # If it does occur, then it is intended for apache, so reset these variables
        $first_col_is_domain_and_port = 0;
        $is_nginx                     = 0;
    }

    # We need to sort the lines by timestamp since we are essentially
    # combining apache logs and nginx logs into one array resulting in
    # the lines no longer being in order from the time they were logged
    my @SORTED_RSD = sort { $a->{timestamp} <=> $b->{timestamp} } @RSD;

    # return only the number of lines requested
    # the array could be double numlines requested if nginx is installed and running
    # and apache has had a lot of direct hits
    return splice( @SORTED_RSD, 0, $numlines );
}

sub lastvisitors {
    my ( $domain, $file, $numlines, $ssl ) = @_;
    require HTTP::Date;

    return if !main::hasfeature('lastvisits');
    require Cpanel::Validate::Domain::Tiny;
    if ( !Cpanel::Validate::Domain::Tiny::validdomainname($domain) ) {
        return 'nolog.html';
    }

    my $safe_domain = Cpanel::WildcardDomain::encode_wildcard_domain($domain);
    Cpanel::LoadModule::load_perl_module('Cpanel::Logs::Find');
    my $accesslog = $ssl ? Cpanel::Logs::Find::find_sslaccesslog($safe_domain) : Cpanel::Logs::Find::find_wwwaccesslog($safe_domain);

    if ( !$accesslog ) {
        return 'nolog.html';
    }

    my ( $line, $lines,  @LINES, $enddate, $now );
    my ( $host, $date,   $tz,    $url,     $http, $code, $size, $referer, $agent );
    my ( $udat, $uhour,  $umin,  $usec );
    my ( $uday, $umonth, $uyear );
    my $timestamp;
    my %USERS;
    my %ORDER;
    my %MAXES;
    my %IPSORT;

    if ( !$numlines ) { $numlines = 1000; }
    $numlines = int $numlines;    #fix security hole

    Cpanel::LoadModule::load_perl_module('Cpanel::SafeRun::Errors');
    $lines = Cpanel::SafeRun::Errors::saferunnoerror( "tail", "-${numlines}", "$accesslog" );
    @LINES = split( /\n/, $lines );

    #See if there's anything to report.  If not, return empty data structures.
    if ( scalar @LINES == 0 ) { return ( \%USERS, \%MAXES, \%IPSORT ); }

    ( undef, undef, undef, $date, undef, undef, undef, undef, undef, undef ) = split( / /, $LINES[-1] );
    $enddate = $date;
    $enddate =~ s/\n//g;
    $enddate =~ s/\[//g;
    $now = sctime();
    my ( $nowdayweek, $nowmonth, $nowday, $nowtime, $nowyear ) = split( /\s/, $now );
    my ( $nowhour, $nowmin, $nowsec ) = split( /:/, $nowtime );

    my $vnum          = 0;
    my $server_offset = Cpanel::Time::Local::get_server_offset_in_seconds();
    foreach $line (@LINES) {
        $line = cleanfield($line);
        $vnum++;
        ( $host, undef, undef, $date, $tz, undef, $url, $http, $code, $size, $referer, $agent ) = split( / /, $line, 12 );
        $agent =~ s/\n//g;
        $date  =~ s/\[//g;
        $http  =~ s/\&quot;//g;
        ( $udat, $uhour, $umin, $usec ) = split( /:/, $date );
        ( $uday, $umonth, $uyear ) = split( /\//, $udat );
        $uday    =~ s/\[//g;
        $tz      =~ s/\]//g;
        $referer =~ s/\&quot;//g;
        $agent   =~ s/\&quot;//g;
        $timestamp = HTTP::Date::str2time($date);
        $timestamp += $server_offset;
        $ORDER{$host}++;
        $MAXES{$host}       = $ORDER{$host};
        $IPSORT{$host}      = $vnum;
        $USERS{$host}{$url} = [ $ORDER{$host}, $umonth, $uday, $uhour, $umin, $usec, $http, $tz, $code, $size, $referer, $agent, $timestamp ];
    }

    return ( \%USERS, \%MAXES, \%IPSORT );
}

sub api2_lastvisitors {
    my %OPTS = @_;
    my @args = ( $OPTS{'domain'}, $OPTS{'numlines'}, $OPTS{'ssl'} );
    my ( $users, $maxes, $ipsort ) = lastvisitors(@args);

    if ( !ref $users ) {
        $Cpanel::CPERROR{'stats'} = 'Unable to open the log file.';
        return;
    }

    my ( @RSD, $host, $path, $s );
    foreach $host ( keys %$users ) {
        foreach $path ( keys %{ $users->{$host} } ) {
            $s = $users->{$host}{$path};

            my %entry = (
                'ip'        => $host,
                'path'      => $path,
                'line'      => $s->[0],
                'timestamp' => $s->[12],
                'version'   => $s->[6],
                'code'      => $s->[8],
                'size'      => $s->[9],
                'referrer'  => ( $s->[10] =~ m/^\s*-\s*$/ ) ? q{} : $s->[10],
                'agent'     => $s->[11],
            );
            push @RSD, \%entry;
        }
    }
    return @RSD;
}

sub sctime {
    my ($time) = time();
    my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst );

    my ($TZ) = defined( $ENV{'TZ'} ) ? ( $ENV{'TZ'} ? $ENV{'TZ'} : 'GMT' ) : '';
    ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime($time);

    $year += 1900;
    return "$DoW[$wday] $MoY[$mon] $mday $hour:$min:$sec $year";
}

sub getmonth {
    my ($mon);
    ( undef, undef, undef, undef, $mon, undef, undef, undef, undef ) = localtime( time() );
    $mon++;
    return $mon;
}

sub getyear {
    my ($year);
    ( undef, undef, undef, undef, undef, $year, undef, undef, undef ) = localtime( time() );
    $year += 1900;
    return $year;
}

sub printsubwebalinks {
    if ( !main::hasfeature("subdomainstats") ) { return (); }

    my ($ddomain);
    my ($dc) = 0;
    foreach $ddomain (@Cpanel::DOMAINS) {
        if ( -f "$Cpanel::homedir/tmp/webalizer/${ddomain}/index.html" ) {
            $dc++;
            print "<a href=\"$ENV{'cp_security_token'}/tmp/$Cpanel::user/webalizer/${ddomain}/index.html\">${ddomain}</a><br>\n";
        }
    }
    if ( $dc == 0 ) {
        print "Unable to find any subdomains with stats pages.\n";
    }
    return "";
}

sub printsubawstatslinks {
    if ( !main::hasfeature("subdomainstats") ) { return (); }

    my ($ddomain);
    my ($dc) = 0;
    my $awstatslang = Cpanel::Locale->get_handle()->cpanel_get_3rdparty_lang('awstats');
    foreach $ddomain (@Cpanel::DOMAINS) {
        next if ( $ddomain eq $Cpanel::CPDATA{'DNS'} );
        my $safe_ddomain = Cpanel::WildcardDomain::encode_wildcard_domain($ddomain);
        if ( -f "$Cpanel::homedir/tmp/awstats/awstats.${safe_ddomain}.conf" ) {
            $dc++;
            print "<a href=\"$ENV{'cp_security_token'}/awstats.pl?config=${safe_ddomain}&lang=$awstatslang\">${ddomain}</a><br>\n";
        }
        else {
            print "<!-- no log for $Cpanel::homedir/tmp/awstats/awstats.${safe_ddomain}.conf -->\n";
        }
    }
    if ( $dc == 0 ) {
        print "Unable to find any subdomains with stats pages.\n";
    }
    return "";
}

sub printsubanalinks {
    if ( !main::hasfeature("subdomainstats") ) { return (); }

    my ($ddomain);
    my ($dc) = 0;
    foreach $ddomain (@Cpanel::DOMAINS) {
        if ( -d "$Cpanel::homedir/tmp/analog/${ddomain}" ) {
            $dc++;
            print "<a href=\"analog.html?domain=${ddomain}\">${ddomain}</a><br>\n";
        }
    }
    if ( $dc == 0 ) {
        print "Unable to find any subdomains with stats pages.\n";
    }
    return "";
}

sub printsublastvisitorslinks {
    if ( !main::hasfeature("subdomainstats") ) { return (); }

    my ($ddomain);
    my ($dc) = 0;
    Cpanel::LoadModule::load_perl_module('Cpanel::Logs::Find');
    foreach $ddomain (@Cpanel::DOMAINS) {
        next if ( $ddomain eq $Cpanel::CPDATA{DNS} );
        if ( ( stat( Cpanel::Logs::Find::find_wwwaccesslog($ddomain) ) )[7] > 0 ) {
            $dc++;

            print "<a href=\"lastvisit.html?domain=${ddomain}\">${ddomain}</a><br>\n";
        }
    }
    if ( $dc == 0 ) {
        print "Unable to find any subdomains with active log files.\n";
    }
    return "";
}

sub cleanfield {
    goto &Cpanel::Encoder::Tiny::safe_html_encode_str;
}

sub bwbar {
    my $percent;

    my $bytes = _get_this_months_total_bw_usage();
    if ( $Cpanel::CPDATA{'BWLIMIT'} == 0 ) {
        $percent = 0;
    }
    else {
        $percent = ( $bytes / $Cpanel::CPDATA{'BWLIMIT'} );
    }

    my $barlength = Cpanel::Math::ceil( $percent * 400 );
    if ( $barlength > 400 ) { $barlength = 400; }
    my $wbarlength = ( 400 - $barlength );
    $percent = Cpanel::Math::ceil( $percent * 100 );

    print "<table><tr><td class=barborder><img src=bar.gif height=8 width=${barlength}><img src=wbar.gif height=8 width=${wbarlength}></td><td>${percent}% used</td></tr></table>";

    return "";
}

sub api2_getthismonthsbwusage {
    return if !$Cpanel::CPDATA{'BWLIMIT'};

    my $bytes = _get_this_months_total_bw_usage();
    return if !defined $bytes;

    return ( { 'bw' => $bytes } );
}

sub _get_this_months_total_bw_usage {
    my $cached = Cpanel::BandwidthDB::UserCache::read_if_mtime_is_this_month($Cpanel::user);
    return $cached if defined $cached;

    Cpanel::AdminBin::Call::call( 'Cpanel', 'bandwidth_call', 'UPDATE_USER_CACHE' );

    $cached = Cpanel::BandwidthDB::UserCache::read_if_mtime_is_this_month($Cpanel::user);
    return $cached if defined $cached;

    #Weird .. we shouldn't get here. Maybe we just changed months or something.
    #Anyway ..

    Cpanel::LoadModule::load_perl_module('Cpanel::BandwidthDB');
    my $bwdb = Cpanel::BandwidthDB::get_reader_for_user();

    my $yrmo = getyear() . '-' . getmonth();

    my $res_ar = $bwdb->get_bytes_totals_as_array(
        grouping => [],
        start    => $yrmo,
        end      => $yrmo,
    );

    return $res_ar->[0][0] || 0;
}

sub _getStatsDirMap {
    my $domains = shift || \@Cpanel::DOMAINS;
    my %DIRMAP;
    foreach my $ddomain (@$domains) {
        next if !$ddomain;
        my $safe_ddomain = Cpanel::WildcardDomain::encode_wildcard_domain($ddomain);
        if ( $ddomain eq $Cpanel::CPDATA{'DNS'} ) {
            $DIRMAP{''}                       = $ddomain;
            $DIRMAP{ 'ssl/' . $safe_ddomain } = $ddomain;
            $DIRMAP{ 'ssl/www.' . $ddomain }  = 'www.' . $ddomain;
        }
        else {
            $DIRMAP{$safe_ddomain} = $ddomain;
            $DIRMAP{ 'ssl/' . $safe_ddomain } = $ddomain;
            if ( $ddomain !~ /^\*/ ) {
                $DIRMAP{ 'www.' . $ddomain }     = 'www.' . $ddomain;
                $DIRMAP{ 'ssl/www.' . $ddomain } = 'www.' . $ddomain;
            }
        }
    }
    return %DIRMAP;
}

sub _fullAwstatsList {
    my $domains_with_data = Cpanel::Stats::AwStats::get_txt_files_per_domain() // {};
    my %DIRMAP            = _getStatsDirMap( [ keys %$domains_with_data ] );
    my $awstatslang       = Cpanel::Locale->get_handle()->cpanel_get_3rdparty_lang('awstats');
    my %addons            = Cpanel::DomainLookup::getmultiparked();

    my @RSD;
    foreach my $dir ( sort { $DIRMAP{$a} cmp $DIRMAP{$b} } keys %DIRMAP ) {
        my $safe_domain = Cpanel::WildcardDomain::encode_wildcard_domain( $DIRMAP{$dir} );
        my $domain      = Cpanel::WildcardDomain::decode_wildcard_domain($safe_domain);
        my $linked_domains;
        next if !exists $domains_with_data->{$safe_domain};    # Skip domains without any data

        if ( grep { $_ eq $domain } keys %addons ) {
            @{$linked_domains} = keys %{ $addons{$domain} };
        }

        if ( $dir =~ m/^ssl\// ) {
            if ( -f $Cpanel::homedir . '/tmp/awstats/ssl/awstats.' . $safe_domain . '.conf' ) {
                push @RSD, { 'domain' => $safe_domain, 'lang' => $awstatslang, 'ssl' => '1', 'txt' => $domain . ' (SSL)', 'addons' => $linked_domains };
            }
        }
        else {
            if ( -f $Cpanel::homedir . '/tmp/awstats/awstats.' . $safe_domain . '.conf' ) {
                push @RSD, { 'domain' => $safe_domain, 'lang' => $awstatslang, 'ssl' => '', 'txt' => $domain, 'addons' => $linked_domains };
            }
        }
    }
    return @RSD;
}

sub fullAwstatsList {
    my @RSD = _fullAwstatsList();
    foreach my $ref (@RSD) {
        print qq{<a href="$ENV{'cp_security_token'}/awstats.pl?config=};
        print $$ref{'domain'};
        print qq{&lang=};
        print $$ref{'lang'};
        print qq{&ssl=};
        print $$ref{'ssl'};
        print qq{">};
        print $$ref{'txt'};
        print qq{</a><br>\n};
    }
    return "";
}

sub _fullWebalizerList {
    my (%DIRMAP) = _getStatsDirMap();

    my @RSD;
    foreach my $dir ( sort { $DIRMAP{$a} cmp $DIRMAP{$b} } keys %DIRMAP ) {
        my $ddomain = $DIRMAP{$dir};
        if ( -e "$Cpanel::homedir/tmp/webalizer/${dir}/index.html" ) {
            my $ssl    = 0;
            my $ssltxt = '';
            if ( $dir =~ /^ssl\// ) { $ssltxt = ' (SSL)'; $ssl = 1; }
            push @RSD,
              {
                'domain' => $ddomain,
                'user'   => $Cpanel::user,
                'dir'    => $dir,
                'txt'    => $ddomain . $ssltxt,
                'ssl'    => $ssl

              };
        }
    }

    return @RSD;
}

sub fullWebalizerList {
    my @RSD = _fullWebalizerList();
    foreach my $ref (@RSD) {
        print qq{<a href="$ENV{'cp_security_token'}/tmp/};
        print $$ref{'user'};
        print qq{/webalizer/};
        print $$ref{'dir'};
        print qq{/index.html">};
        print $$ref{'txt'};
        print qq{</a><br>\n};
    }
    return "";
}

sub _fullAnalogList {
    my (%DIRMAP) = _getStatsDirMap();

    my @RSD;
    foreach my $dir ( sort { $DIRMAP{$a} cmp $DIRMAP{$b} } keys %DIRMAP ) {
        my $ddomain = $DIRMAP{$dir};
        if ( -d "$Cpanel::homedir/tmp/analog/${dir}" ) {
            my $ssl    = '';
            my $ssltxt = '';
            my $sslopt = 0;
            if ( $dir =~ /^ssl\// ) { $sslopt = 1; $ssltxt = ' (SSL)'; $ssl = '&ssl=1'; }
            push( @RSD, { domain => $ddomain, ssl => $sslopt, txt => $ddomain . $ssltxt } );

        }
    }

    return @RSD;
}

sub fullAnalogList {
    my @RSD = _fullAnalogList();
    foreach my $ref (@RSD) {
        print qq{<a href="analog.html?domain=};
        print $$ref{'domain'};
        print qq{&ssl=};
        print $$ref{'ssl'};
        print qq{">};
        print $$ref{'txt'};
        print qq{</a><br>\n};
    }
    return "";
}

sub _fullLastVisitorsList {
    my (%DIRMAP) = _getStatsDirMap();

    my @RSD;
    Cpanel::LoadModule::load_perl_module('Cpanel::Logs::Find');
    foreach my $dir ( sort { $DIRMAP{$a} cmp $DIRMAP{$b} } keys %DIRMAP ) {
        my $ddomain      = $DIRMAP{$dir};
        my $safe_ddomain = Cpanel::WildcardDomain::encode_wildcard_domain($ddomain);

        my $accesslog     = Cpanel::Logs::Find::find_wwwaccesslog($safe_ddomain);
        my $ssl_accesslog = Cpanel::Logs::Find::find_sslaccesslog($safe_ddomain);

        # If it is nginx, then we have to check to see if the apache logs too
        my $apache_accesslog     = '';
        my $ssl_apache_accesslog = '';
        if ( Cpanel::Logs::path_is_nginx_domain_log($accesslog) ) {

            # Taken from Cpanel::Logd

            # UGMO 1 global internal: NGINX log can exist at this point so we need to drop it for this pass:
            local @Cpanel::Logs::Find::_default_log_locations = @Cpanel::Logs::Find::_default_log_locations;
            shift @Cpanel::Logs::Find::_default_log_locations;

            # UGMO 2 global internal: the cached _default_log_locations is also cached based on mtime so we need to drop it here too
            local @Cpanel::Logs::Find::_log_locations = @Cpanel::Logs::Find::_log_locations;
            shift @Cpanel::Logs::Find::_log_locations;

            $apache_accesslog     = Cpanel::Logs::Find::find_wwwaccesslog($safe_ddomain);
            $ssl_apache_accesslog = Cpanel::Logs::Find::find_sslaccesslog($safe_ddomain);
        }

        my $ssl    = '';
        my $ssltxt = '';
        my $sslopt = 0;
        if ( $dir =~ /^ssl\// ) {
            $sslopt = 1;
            $ssltxt = ' (SSL)';
            $ssl    = '&ssl=1';
            next if !-s $ssl_accesslog && !-s $ssl_apache_accesslog;
        }
        else {
            next if !-s $accesslog && !-s $apache_accesslog;
        }
        push( @RSD, { 'domain' => $ddomain, 'ssl' => $sslopt, 'txt' => $ddomain . $ssltxt } );

    }

    return @RSD;
}

sub fullLastVisitorsList {
    my @RSD = _fullLastVisitorsList();
    foreach my $ref (@RSD) {
        print qq{<a href="lastvisit.html?domain=};
        print $$ref{'domain'};
        print qq{&ssl=};
        print $$ref{'ssl'};
        print qq{">};
        print $$ref{'txt'};
        print qq{</a><br>\n};
    }
    return "";
}

=head2 list_site_errors(DOMAIN, LOG, MAXLINES)

Lists the site errors for a given domain and log.

=head3 ARGUMENTS

=over

=item DOMAIN - string

The domain of the site you want to look at.

=item LOG - string

One of the following:

=over

=item - error - web server error log.

=item - suexec - suexec error log.

=back

=item MAXLINES - integer

Maximum number of lines to scan when searching for errors for this account. Must be between 1 and 5000 inclusive.

=back

=head3 RETURNS

Arrayref of hashrefs each with the following parts:

=over

=item date - timestamp | undef

Date/Time of the entry if present.

=item entry - string

Matching line from the log. This includes the complete log line.

=back

=head3 THROWS

=over

=item When the domain is missing.

=item When the domain does not belong to the current user.

=item When the log parameter is not one of the known logs.

=item When the maxlines parameter is < 1 or > 5000

=item When the maxlines is not numeric.

=item When the requested log can not be read for some reason.

=back

=cut

sub list_site_errors {
    my ( $domain, $log, $maxlines ) = @_;

    if ( ( defined($log) ) && ( grep { $_ eq $log } @{ AVAILABLE_LOGS() } ) ) {
        if ( my $method = Cpanel::Stats->can("list_${log}_log") ) {
            return $method->( $domain, $maxlines );
        }
    }

    die Cpanel::Exception::create(
        'InvalidParameter',
        "Log “[_1]” is not valid. Enter one of the following: [list_or_quoted,_2].",
        [ $log, AVAILABLE_LOGS ]
    );
}

=head2 list_error_log(DOMAIN, MAXLINES)

Get the entries from the web server error log for the passed domain. Limit search to the last MAXLINES of the file.
This function finds lines that match the users home directory or username, depending on the log requested. This is a
dispatch method which calls an implementation specific processing method defined for a log. Refer to list_error_log or
list suexec_log for specific implementation details.

=head3 ARGUMENTS

=over

=item DOMAIN - string

The domain of the site you want to look at.

=item MAXLINES - integer

Maximum number of lines to scan when searching for errors for this account. Must be between 1 and 5000.

=back

=head3 RETURNS

Arrayref of hashrefs each with the following parts:

=over

=item date - timestamp | undef

Date/Time of the entry if present as a UNIX timestamp, possibly with subsecond values.

=item entry - string

Matching line from the log. This includes the complete log line.

=back

=head3 THROWS

=over

=item When the domain is missing.

=item When the domain does not belong to the current user.

=item When the maxlines parameter is < 1 or > 5000

=item When maxlines is not numeric.

=item When the requested log can not be read for some reason.

=back

=cut

sub list_error_log {
    my ( $domain, $maxlines ) = @_;

    _validate_domain($domain);
    require Cpanel::Logs::Find;
    require Cpanel::ConfigFiles::Apache;
    require Cpanel::PwCache;
    my $localtime = Time::Piece->new();

    my @entries;
    my $homedir   = $Cpanel::homedir // Cpanel::PwCache::gethomedir($>);
    my $error_log = Cpanel::Logs::Find::find_wwwerrorlog($domain);
    my $lines     = _list_last_lines_matching( $error_log, _path_match_regex($homedir), $maxlines );

    for my $line (@$lines) {
        my $epoch;
        my $micro;
        my @parts = split( /[\[\]]/, $line, 3 );
        if ( scalar @parts == 3 ) {

            # Mon Jul 08 09:05:52.289448 2019
            $parts[1] =~ s/\.(\d{6})//;
            $micro = $1 if $1;

            # Mon Jul 08 09:05:52 2019
            my $strptime = eval { $localtime->strptime( $parts[1], "%a %b %d %H:%M:%S %Y" ) };
            $epoch = sprintf( "%u.%u", $strptime->epoch, $micro ) * 1.0 if $strptime;
        }

        push @entries, {
            'date'  => $epoch,
            'entry' => $line
        };

    }

    return \@entries;
}

=head2 list_suexec_log(DOMAIN, MAXLINES)

Get the entries from the suexec error log for the passed domain. Limit search to the last MAXLINES of the file.
This function looks for lines matching the users home folder and/or their cpanel username.

=head3 ARGUMENTS

=over

=item DOMAIN - string

The domain of the site you want to look at.

=item MAXLINES - integer

Maximum number of lines to scan when searching for errors for this account. Must be between 1 and 5000.

=back

Arrayref of hashrefs each with the following parts:

=over

=item date - timestamp | undef

Date/Time of the entry as a UNIX timestamp if present.

=item entry - string

Matching line from the log. This includes the complete log line.

=back

=head3 THROWS

=over

=item When the domain is missing.

=item When the domain does not belong to the current user.

=item When the maxlines parameter is < 1 or > 5000

=item When the maxlines is not numeric.

=item When the requested log can not be read for some reason.

=back

=cut

sub list_suexec_log {
    my ( $domain, $maxlines ) = @_;

    _validate_domain($domain);
    require Cpanel::ConfigFiles::Apache;
    require Cpanel::PwCache;

    my @entries;
    my $homedir      = $Cpanel::homedir // Cpanel::PwCache::gethomedir($>);
    my $log          = Cpanel::ConfigFiles::Apache::apache_paths_facade()->dir_logs() . '/suexec_log';
    my $suexec_regex = '(?:' . _path_match_regex($homedir) . '|' . _user_match_regex( $Cpanel::user, $Cpanel::USERDATA{'uid'}, $Cpanel::USERDATA{'gid'} ) . ')';
    my $lines        = _list_last_lines_matching( $log, $suexec_regex, $maxlines );
    my $localtime    = Time::Piece->new();

    for my $line (@$lines) {
        my $epoch = undef;
        my @parts = split( /[\[\]]/, $line, 3 );
        if ( scalar @parts == 3 ) {

            # 2019-07-08 10:32:14
            my $strptime = eval { $localtime->strptime( $parts[1], "%Y-%m-%d %H:%M:%S" ) };
            $epoch = int $strptime->epoch if $strptime;
        }

        push @entries, {
            'date'  => $epoch,
            'entry' => $line
        };

    }

    return \@entries;
}

=head2 _list_last_lines_matching(PATH, PATTERN, MAXLINES) [PRIVATE]

Helper to find the lines of a file that match the pattern from the end of the file to MAXLINES from the end of the file.

=head3 ARGUMENTS

=over

=item PATH - string

Full path to the log file to scan.

=item PATTERN - regex

Expression used to determine if a line matches the criteria for inclusion in the output list.

=item MAXLINES - integer

Maximum number of lines to scan when searching for lines in this file. Must be between 1 and 5000.

=back

=head3 RETURNS

Arrayref of lines that match the criteria. The first record is the newest log entry.

=head3 THROWS

=over

=item When the path is missing.

=item When the file provided in the path can not be read.

=item When the pattern parameter is missing.

=item When the maxlines parameter is < 1 or > 5000.

=item When the maxlines is not numeric.

=back

=cut

sub _list_last_lines_matching {
    my ( $path, $pattern, $maxlines ) = @_;

    die Cpanel::Exception::create( 'InvalidParameter', 'The “[_1]” parameter is required.',            ['path'] )                         if !$path;
    die Cpanel::Exception::create( 'InvalidParameter', 'The “[_1]” parameter is required.',            ['pattern'] )                      if !$pattern;
    die Cpanel::Exception::create( 'InvalidParameter', 'The “[_1]” parameter is required.',            ['maxlines'] )                     if !$maxlines;
    die Cpanel::Exception::create( 'InvalidParameter', 'The “[_1]” parameter must be numeric.',        ['maxlines'] )                     if $maxlines =~ /\D/;
    die Cpanel::Exception::create( 'InvalidParameter', 'The “[_1]” parameter must be greater than 0.', ['maxlines'] )                     if ( int $maxlines < 1 );
    die Cpanel::Exception::create( 'InvalidParameter', 'The “[_1]” parameter must not exceed “[_2]”.', [ 'maxlines', MAX_READ_LINES() ] ) if ( int $maxlines > MAX_READ_LINES );

    require File::ReadBackwards;
    my @lines;

    if ( my $reader = File::ReadBackwards->new($path) ) {
        while ( defined( my $line = $reader->readline ) && scalar @lines < $maxlines ) {
            chomp($line);
            push @lines, $line if ( $line =~ $pattern );
        }
        $reader->close;
    }
    else {
        if ( !$!{'ENOENT'} ) {
            die Cpanel::Exception::create( 'IO::FileOpenError', [ path => $path, mode => '<', error => $! ] );
        }
    }

    return \@lines;
}

=head2 _validate_domain(DOMAIN) [PRIVATE]

Checks if the domain is valid for this user.

=head3 ARGUMENTS

=over

=item DOMAIN - string

The domain to validate.

=back

=head3 RETURNS

1 when its valid.

=head3 THROWS

=over

=item When the domain is improperly formatted.

=item When the domain is not owned by the current cpanel user.

=back

=cut

sub _validate_domain {
    my ($domain) = @_;

    require Cpanel::Validate::Domain;
    Cpanel::Validate::Domain::valid_domainname_for_customer_or_die($domain);

    require Cpanel::AcctUtils::DomainOwner;
    if ( !Cpanel::AcctUtils::DomainOwner::is_domain_owned_by( $domain, $Cpanel::user ) ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The domain “[_1]” is not configured for this account.', [$domain] );
    }

    return 1;
}

sub _rawlogs {
    my ( $mday, $mon, $year );
    ( undef, undef, undef, $mday, $mon, $year, undef, undef, undef ) = localtime( time() );
    $mon++;
    $year += 1900;

    my $PERMIT_MEMORY_CACHE = 1;

    my $cache = Cpanel::Config::userdata::Cache::load_cache( $Cpanel::user, $PERMIT_MEMORY_CACHE );
    my %DOMAINS;

    # $cache is a HASHREF
    # $cache keys are domains
    # $cache values are a ARRAYREF with ( 0 $owner, 1 $reseller, 2 $type, 3 $parent, 4 $docroot )
    if ( $cache && %$cache ) {
        for my $domain ( keys %$cache ) {
            if ( $cache->{$domain}->[2] eq 'parked' || $cache->{$domain}->[2] eq 'addon' ) {
                push @{ $DOMAINS{ $cache->{$domain}->[3] } }, $domain;
            }
            else {
                $DOMAINS{$domain} ||= [];

            }
        }
    }

    my (@RSD);
    my ( $safe_domain, $info, $filename );

    $locale ||= Cpanel::Locale->get_handle();
    my $never_text = $locale->maketext('Never');
    my $nonetxt    = Cpanel::Math::get_none_text();

    Cpanel::LoadModule::load_perl_module('Cpanel::Logs::Find');
    foreach my $domain ( sort keys %DOMAINS ) {
        $safe_domain = Cpanel::WildcardDomain::encode_wildcard_domain($domain);
        if ( ( ( $filename, $info ) = Cpanel::Logs::Find::find_wwwaccesslog_with_info($safe_domain) )[0] ) {
            push(
                @RSD,
                {
                    'updatetime'      => $info->[1],
                    'humanupdatetime' => ( $info->[1] ? scalar localtime( $info->[1] ) : $never_text ),
                    'humansize'       => (
                        $info->[0]
                        ? Cpanel::Math::_toHumanSize( $info->[0] )
                        : $nonetxt

                    ),
                    'size'           => $info->[0],
                    'file'           => $filename,
                    'link'           => "$ENV{'cp_security_token'}/getaccesslog/accesslog_${safe_domain}_${mon}_${mday}_${year}.gz",
                    'domain'         => $domain,
                    'txt'            => $domain,
                    'type'           => 'standard',
                    'linked_domains' => [ map { { 'domain' => $_ } } sort @{ $DOMAINS{$domain} } ]
                }
            );
        }
        if ( ( ( $filename, $info ) = Cpanel::Logs::Find::find_sslaccesslog_with_info($safe_domain) )[0] ) {
            push(
                @RSD,
                {
                    'updatetime'      => $info->[1],
                    'humanupdatetime' => ( $info->[1] ? scalar localtime( $info->[1] ) : $never_text ),
                    'humansize'       => (
                        $info->[0]
                        ? Cpanel::Math::_toHumanSize( $info->[0] )
                        : $nonetxt
                    ),
                    'size'   => $info->[0],
                    'file'   => $filename,
                    'link'   => "$ENV{'cp_security_token'}/getsslaccesslog/sslaccesslog_${safe_domain}_${mon}_${mday}_${year}.gz",
                    'domain' => $domain . ' (SSL)',
                    'txt'    => $domain,
                    'type'   => 'ssl'
                }
            );
        }
        my $ftp_domain = "ftp.$safe_domain";
        if ( ( ( $filename, $info ) = Cpanel::Logs::Find::find_ftpaccesslog_with_info($ftp_domain) )[0] ) {
            push(
                @RSD,
                {
                    'updatetime'      => $info->[1],
                    'humanupdatetime' => ( $info->[1] ? scalar localtime( $info->[1] ) : $never_text ),
                    'humansize'       => (
                        $info->[0]
                        ? Cpanel::Math::_toHumanSize( $info->[0] )
                        : $nonetxt
                    ),
                    'size'   => $info->[0],
                    'file'   => $filename,
                    'link'   => "$ENV{'cp_security_token'}/getftpaccesslog/ftpaccesslog_${ftp_domain}_${mon}_${mday}_${year}.gz",
                    'domain' => $domain . ' (ftp)',
                    'txt'    => $domain,
                    'type'   => 'ftp'
                }
            );
        }

    }

    return \@RSD;
}

=head2 _path_match_regex(PATH) [PRIVATE]

Builds a regex used to match the provided path, in whole or as a parent, such as a homedir in a log entry.

=head3 ARGUMENTS

=over

=item PATH - string

An absolute path.

=back

=head3 RETURNS

A regular expression.

=head3 THROWS

=over

=item If the PATH is missing.

=back

=head2 _user_match_regex(USER, UID, GID) [PRIVATE]

Builds a regex used to match the provided user name, with optional uid and gid.

=head3 ARGUMENTS

=over

=item USER - string

A user name.

=item UID - string

An optional numeric User ID.

=item GID - string

An optional numeric Group ID.

=back

=head3 RETURNS

A regular expression.

=head3 THROWS

=over

=item If the USER is missing.

=item If optional UID or GID are not whole numbers.

=back

=cut

{
    my $field_separator = qr{[\s\[\]():]};
    my $field_begin     = qr{\A|$field_separator};
    my $field_end       = qr{\Z|$field_separator};

    sub _path_match_regex {
        my ($path) = @_;
        die Cpanel::Exception::create( 'InvalidParameter', 'The “[_1]” parameter is required.', ['path'] ) if !$path;

        # [Tue Jun 02 09:40:28.529831 2020] [core:error] [pid 24388] (13)Permission denied: [client 172.16.1.13:60414] AH00132: file permissions deny server access: /home/knowledge/public_html/index.html
        return qr{
            $field_begin
            \Q$path\E
            (?:$field_end|/) # May also end in a path separator (is a parent path)
        }xms;
    }

    sub _user_match_regex {
        my ( $user, $uid, $gid ) = @_;
        die Cpanel::Exception::create( 'InvalidParameter', 'The “[_1]” parameter is required.',            ['user'] ) if !$user;
        die Cpanel::Exception::create( 'InvalidParameter', 'The parameter “[_1]” must be a whole number.', ['uid'] )  if defined $uid && $uid !~ m{^[0-9]+$};
        die Cpanel::Exception::create( 'InvalidParameter', 'The parameter “[_1]” must be a whole number.', ['gid'] )  if defined $gid && $gid !~ m{^[0-9]+$};

        my @user_matchers = ( quotemeta($user) );

        # [2020-06-02 14:16:05]: uid: (1234/user) gid: (1235/user) cmd: my.cgi
        push @user_matchers, quotemeta("$uid/$user") if defined $uid;
        push @user_matchers, quotemeta("$gid/$user") if defined $gid;    # The log contains the primary group name but stay safe and only match if it is the same as user name

        if ( defined $uid && defined $gid ) {

            # [2020-06-02 14:16:05]: error: target uid/gid (1335/1329) mismatch with directory (1335/1329) or program (0/0) or trusted user (0/10)
            push @user_matchers, quotemeta("$uid/$gid");

            # Match the commonly used uid:gid pattern. This is limited to uid/gid length >= 3 to avoid the possibility of confusing a log timestamp with uid:gid.
            # Since MINUID and MINGID default is currently three digits, attempting to match a shorter uid:gid should not occur under normal circumstances.
            push @user_matchers, quotemeta("$uid:$gid") if length $uid >= 3 && length $gid >= 3;
        }

        my $user_match = join '|', @user_matchers;
        return qr{
            $field_begin
            (?: $user_match )
            $field_end
        }xms;
    }

}

my $bandwidth_feature_allow_demo = { needs_feature => 'bandwidth', allow_demo => 1 };

our %API = (
    'listawstats' => {
        'func'     => '_fullAwstatsList',
        needs_role => 'WebServer',
        allow_demo => 1,
    },
    'listwebalizer' => {
        'func'     => '_fullWebalizerList',
        needs_role => 'WebServer',
        allow_demo => 1,
    },
    'listanalog' => {
        'func'     => '_fullAnalogList',
        needs_role => 'WebServer',
        allow_demo => 1,
    },
    'listlastvisitors' => {
        'func'     => '_fullLastVisitorsList',
        needs_role => 'WebServer',
        allow_demo => 1,
    },
    'listrawlogs' => {
        'func'     => '_rawlogs',
        needs_role => 'WebServer',
        allow_demo => 1,
    },
    'lastvisitors' => {
        needs_role => 'WebServer',
        allow_demo => 1,
    },
    'lastapachehits' => {
        needs_role    => 'WebServer',
        needs_feature => 'lastvisits',
        allow_demo    => 1,
        sort_methods  => {
            'line'      => 'numeric',
            'ip'        => 'ipv4',
            'timestamp' => 'numeric',
            'size'      => 'numeric',
        },
    },
    'getmonthlybandwidth'       => $bandwidth_feature_allow_demo,
    'getmonthlydomainbandwidth' => $bandwidth_feature_allow_demo,
    'getthismonthsbwusage'      => { allow_demo => 1 },
);

sub api2 {
    my ($func) = @_;
    return { %{ $API{$func} } } if $API{$func};
    return;
}

1;
