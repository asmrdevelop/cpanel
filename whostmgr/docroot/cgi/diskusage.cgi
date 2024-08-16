#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - whostmgr/docroot/cgi/diskusage.cgi      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Form            ();
use Whostmgr::HTMLInterface ();
use Whostmgr::ACLS          ();
use Cpanel::Encoder::Tiny   ();
use Cpanel::Binaries        ();
use Cpanel::Server::Type    ();
use Cpanel::Locale 'lh';
use Cpanel::SafeRun::Errors ();
use CGI::Carp               qw(fatalsToBrowser);
use GD;

alarm(60);

Whostmgr::ACLS::init_acls();

if ( !Whostmgr::ACLS::hasroot() || Cpanel::Server::Type::is_dnsonly() ) {
    print "Content-Type: text/html\r\n\r\n";
    Whostmgr::HTMLInterface::defheader( '', '', '/cgi/diskusage.cgi', undef, undef, undef, undef, undef, 'show_current_disk_usage' );
    print <<'EOM';

<br />
<br />
<div><h1>Permission denied</h1></div>
EOM
    Whostmgr::HTMLInterface::deffooter();
    exit;
}

my %FORM = Cpanel::Form::parseform();

if ( !exists $FORM{'cgiaction'} ) {
    printPage();
}
elsif ( $FORM{'cgiaction'} eq 'diskusage' ) {
    if ( !defined( $FORM{'dev'} ) ) { print "Content-Type: image/png"; return; }
    my %stats = load_df();
    drawImage( $stats{ $FORM{'dev'} }[4] );
}
elsif ( $FORM{'cgiaction'} eq 'bar' ) {
    if ( !defined( $FORM{'pix'} ) ) { print "Content-Type: image/png"; return; }
    drawBar( $FORM{'pix'} );
}
else {
    printPage();
}

#################################################
#
#################################################
sub printPage {
    print "Content-Type: text/html\r\n\r\n";

    my %stats = load_df();
    Whostmgr::HTMLInterface::defheader( lh()->maketext("Disk Usage"), undef, undef, undef, undef, undef, undef, undef, 'show_current_disk_usage' );
    print <<"EOM";

<br />
<fieldset><legend>Current Disk Usage Information</legend><br/>
<div>
<table width="90%" cellspacing="1" cellpadding="0" border="0">
    <th>
        <td>Device</td>
        <td>Size</td>
        <td>Used</td>
        <td>Available</td>
        <td>Percent Used</td>
        <td>Mount Point</td>
    </th>
EOM
    my $bg = "1";
    foreach my $dev ( sort keys %stats ) {
        my $safe_mnt = Cpanel::Encoder::Tiny::safe_html_encode_str( $stats{$dev}[5] );
        print <<"EOM";
    <tr class="tdshade${bg}">
        <td width="50"><img src="./diskusage.cgi?cgiaction=diskusage&dev=${dev}"></td>
        <td width="100">$dev</td>
        <td width="100">$stats{$dev}[1]</td>
        <td width="100">$stats{$dev}[2]</td>
        <td width="100">$stats{$dev}[3]</td>
        <td width="100">$stats{$dev}[4]%</td>
        <td>$safe_mnt</td>
    </tr>
EOM
        $bg = $bg eq '1' ? '2' : '1';
    }
    print <<'EOM';
</table>
</div>
<br/>
</fieldset>
<br/>
EOM
    doIoStat();
    Whostmgr::HTMLInterface::deffooter();

    return;
}

##################################################
#
##################################################
sub load_df {
    my %df_stats;
    my $lvm;

    open( DF, "-|" ) || exec( "df", "-Ph" );
    while (<DF>) {
        if ( !( /^Filesystem/ || /^none/ ) ) {
            my @stats = split( /\s+/, $_ );

            if ( $stats[0] ne '' ) {
                $lvm = $stats[0];
            }

            if ( $stats[0] eq '' && $lvm ) {
                $stats[0] = $lvm;
            }

            next if ( $stats[5] !~ m/^\// || $stats[0] !~ m/^(\/|simfs)/ );

            # case 86609: suppress duplicate entries for a device due to virtfs bind mounts
            next if ( exists( $df_stats{ $stats[0] } ) );

            @{ $df_stats{ $stats[0] } } = @stats;
            $df_stats{ $stats[0] }[4] =~ s/\%$//;
        }
    }
    close(DF);
    return %df_stats;
}

####################################################
# drawImage -
#    Takes one parameter, percentage.  The function
# will draw and output a pie graph. A portion of the
# graph will be alter-colored depending on the percentage
# specified.
####################################################
sub drawImage {
    my ($perc) = @_;

    print "Content-Type: image/png\r\n\r\n";
    my $image  = new GD::Image( 50, 50 );
    my $black  = $image->colorAllocate( 0,   0,   0 );
    my $white  = $image->colorAllocate( 255, 255, 255 );
    my $owhite = $image->colorAllocate( 254, 254, 254 );
    my $red    = $image->colorAllocate( 200, 0,   0 );
    my $yellow = $image->colorAllocate( 200, 0,   0 );
    my $dgreen = $image->colorAllocate( 1,   77,  95 );

    $image->fill( 0, 0, $white );
    $image->transparent($white);
    $image->interlaced('true');

    #$image->rectangle(0,0,49,49,$black);
    $image->filledEllipse( 24, 24, 45, 45, $black );

    # Draw 'consumed' space in red if above 80%
    if ( $perc >= 80 ) {
        $image->filledArc( 24, 24, 45, 45, 0, 360 / ( 100 / $perc ), $red );
    }
    elsif ( $perc >= 60 ) {
        $image->filledArc( 24, 24, 45, 45, 0, 360 / ( 100 / $perc ), $yellow );
    }
    elsif ( $perc > 0 ) {
        $image->filledArc( 24, 24, 45, 45, 0, 360 / ( 100 / $perc ), $dgreen );
    }

    $image->ellipse( 24, 24, 45, 45, $black );

    binmode STDOUT;

    print $image->png;
}

############################################################
#
############################################################
sub drawBar {
    my ($pix) = @_;
    $pix = ( $pix / 10 ) + 1;

    print "Content-Type: image/png\r\n\r\n";

    my $image  = new GD::Image( $pix, 10 );
    my $dgreen = $image->colorAllocate( 1,   77,  95 );
    my $white  = $image->colorAllocate( 255, 255, 255 );

    $image->fill( 0, 0, $dgreen );
    binmode STDOUT;

    print $image->png;
}

############################################################
#
############################################################
sub doIoStat {
    my $iostat_bin = Cpanel::Binaries::path('iostat');

    if ( !-x $iostat_bin ) {
        print "Could not find \`iostat\` program, please ensure iostat is installed (normally included with the \"sysstat\" package)<br>\n";
        return;
    }
    else {
        my $INPUT = Cpanel::SafeRun::Errors::saferunallerrors( $iostat_bin, '-d' );

        # Do our linux iostat stuff here.
        my @lines = split( /\n+/, $INPUT );
        if ( $#lines < 2 ) {
            print "Not enough information returned from iostat output for display, this is normal on some VPS systems.";
            return;
        }
        print <<'EOM';
<fieldset><legend>IO Statistics</legend>
<div>
<table width="90%" border="0">
    <tr>
        <td>Device</td>
        <td>Trans./Sec</td>
        <td>Blocks Read/sec</td>
        <td>Blocks Written/Sec</td>
        <td>Total Blocks Read</td>
        <td>Total Blocks Written</td>
    </tr>
EOM
        my $bg = 1;
        foreach my $line (@lines) {
            if ( !( $line =~ /^Linux/ || $line =~ /^Device/ ) ) {
                if   ( $bg == 1 ) { $bg = 2; }
                else              { $bg = 1; }
                my @stats = split( /\s+/, $line );
                print "<tr class=\"tdshade${bg}\">";
                my $index = 0;
                foreach my $item (@stats) {
                    print '<td>';
                    if ( $index == 2 || $index == 3 ) {
                        print qq{<img align="middle" src="./diskusage.cgi?cgiaction=bar&pix=${item}">&nbsp;};
                    }
                    print "$item</td>\n";
                    $index++;
                }
                print '</tr>';
            }
        }
        print "</table>\n</div>\n</fieldset>\n";
    }

    return;
}
