package Whostmgr::ServiceSwitch::ftpserver;

# cpanel - Whostmgr/ServiceSwitch/ftpserver.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Whostmgr::ServiceSwitch ();
use Whostmgr::UI            ();

sub switch {
    my %OPTS = @_;

    my ( $current_ftpserver, $available_ref, $conf_ref ) = Whostmgr::ServiceSwitch::getcfg('ftpserver');
    my $ftpserver      = $OPTS{'ftpserver'};
    my $security_token = $ENV{'cp_security_token'} || '';

    if ( $current_ftpserver eq $ftpserver ) {
        print "Already configured for $ftpserver...skipping.\n";
        return 1;
    }

    my $html_yn = !$Whostmgr::UI::nohtml;

    my $format_cr = sub {
        my $before = $html_yn ? '<span class="b2">' : q<>;
        my $after  = $html_yn ? '</span><br>'       : q<>;

        return $before . $_[0] . $after . "\n";
    };

    if ( $ftpserver eq 'proftpd' || $ftpserver eq 'pure-ftpd' ) {
        print $format_cr->('Installing new FTP server …');
    }
    elsif ( $ftpserver eq 'disabled' ) {
        print $format_cr->('Shutting down FTP server …');
    }
    else {
        print "Invalid FTP server type specified.\n";
        return;
    }

    print '<pre>' if $html_yn;

    require Cpanel::Rlimit;
    Cpanel::Rlimit::set_rlimit_to_infinity();

    my @html_args = $html_yn ? ('--html') : ();
    system( '/usr/local/cpanel/scripts/setupftpserver', $ftpserver, @html_args );

    if ( $ftpserver ne 'disabled' ) {
        print '</pre><br>' if $html_yn;

        print $format_cr->('FTP Server Install Complete');

        my $sentence = 'You should now check and adjust the FTP settings';

        my $link_text = 'FTP Server Configuration';
        if ($html_yn) {
            $sentence .= '<br>';

            my $url = "${security_token}/scripts2/ftpconfiguration";

            substr( $link_text, 0, 0 ) = qq[<a href="$url">];
            $link_text .= '</a>';
        }
        else {
            $sentence .= q< >;
        }

        $sentence .= "by visiting WHM’s $link_text interface.";

        print $format_cr->($sentence);
    }

    return 1;
}

1;
