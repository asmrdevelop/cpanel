package Cpanel::LegacyLogin;

# cpanel - Cpanel/LegacyLogin.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

# This module contains the HTML-parsing code for cpsrvd templates
# prior to cPanel & WHM 11.32. It is not loaded except to support
# legacy login themes.

use cPstrict;

use Cpanel::App                ();
use Cpanel::Encoder::Tiny      ();
use Cpanel::Encoder::URI       ();
use Cpanel::LoginTheme         ();
use Cpanel::MagicRevision      ();    # PPI USE OK -- This module is only used in a s///e regex and this is difficult to parse.
use Cpanel::Version::Full      ();
use Cpanel::Config::LoadCpConf ();

use constant _ENOENT => 2;

our $VAR_CPANEL_CPSRVD_DIR = '/var/cpanel/cpsrvd';

sub get_html_header {
    my $logintheme = ( shift || Cpanel::LoginTheme::get_login_theme() );
    return _process_old_template_file(
        Cpanel::LoginTheme::getloginfile(
            'docname'    => 'header',
            'docext'     => 'html',
            'appname'    => $Cpanel::App::appname,
            'logintheme' => $logintheme
        ),
        'login_theme' => $logintheme
    );
}

sub get_html_footer {
    my $logintheme = ( shift || Cpanel::LoginTheme::get_login_theme() );
    return _process_old_template_file(
        Cpanel::LoginTheme::getloginfile(
            'docname'    => 'footer',
            'docext'     => 'html',
            'appname'    => $Cpanel::App::appname,
            'logintheme' => $logintheme
        ),
        'login_theme' => $logintheme
    );
}

sub get_logout_html {
    my $skiphttpauth = shift;
    return _process_old_template_file( '/usr/local/cpanel/etc/logout.html', 'clearhttpauth' => ( $skiphttpauth ? 0 : 1 ) );
}

sub encode_form {
    my $formref = shift;
    my $format  = shift;
    return unless ( $formref && $format );
    my $str = '';
    foreach my $key ( keys %{$formref} ) {
        if ( $format eq 'table' ) {
            $str .= '<tr><td class="formkey">' . Cpanel::Encoder::Tiny::safe_html_encode_str($key) . '</td><td class="formvalue">' . Cpanel::Encoder::Tiny::safe_html_encode_str( $formref->{$key} ) . '</td></tr>';
        }
        elsif ( $format eq 'html' ) {
            $str .= '<input type="hidden" name="' . Cpanel::Encoder::Tiny::safe_html_encode_str($key) . '" value="' . Cpanel::Encoder::Tiny::safe_html_encode_str( $formref->{$key} ) . '">';
        }
        elsif ( $format eq 'param' ) {
            $str .= Cpanel::Encoder::URI::uri_encode_str($key) . '=' . Cpanel::Encoder::URI::uri_encode_str( $formref->{$key} ) . '&';
        }
    }

    if ( $format eq 'param' ) {
        $str =~ s/\&$//;
    }

    return $str;
}

sub whm_logout {
    my ( $socket, $logintheme ) = @_;
    my $cpconf = Cpanel::Config::LoadCpConf::loadcpconf();

    my $buffer;
    $buffer .= get_html_header($logintheme);
    my $html_safe_logintheme = Cpanel::Encoder::Tiny::safe_html_encode_str($logintheme);
    if ( open( my $login_fh, '<', $cpconf->{'root'} . '/whostmgr/docroot/logout.html' ) ) {
        local $/;
        $buffer .= readline($login_fh);
        $buffer =~ s/\%login_theme\%/$html_safe_logintheme/g;
        close($login_fh);
    }
    $buffer .= get_logout_html( $cpconf->{'skiphttpauth'} );
    $buffer .= get_html_footer($logintheme);

    return ( 1, \$buffer );
}

sub logout {
    my ( $socket, $logintheme, %OPTS ) = @_;

    my $buffer;
    $buffer .= get_html_header($logintheme);
    if ( $OPTS{'logout_html'} ) {
        $buffer .= $OPTS{'logout_html'};
    }
    else {
        my $uri_theme = Cpanel::Encoder::URI::uri_encode_str($logintheme);
        $buffer .= qq{
                <br><br>
                <center>
                <font face="verdana, arial,helvetica,sans-serif" size="1">
                <b> You have been logged out. Thank you for using cPanel!</b>
                <br>
                <br>
                <a href="/?login_theme=$uri_theme">Click here to log in again.</a>
                </font></center>
        };
    }
    $buffer .= get_logout_html();
    $buffer .= get_html_footer($logintheme);

    return ( 1, \$buffer );
}

sub login {
    my ( $socket, $logintheme, %OPTS ) = @_;

    my $cpconf = $OPTS{'cpconf'};

    my $buffer;
    $buffer .= get_html_header($logintheme);
    $buffer .= _trial_banner( \%OPTS );

    if ( $OPTS{'notefailure'} ) {
        $buffer .= qq{<b><font color="#FF0000">Login Attempt Failed!</font></b><br>};
    }
    if ( $OPTS{'message'} ) {
        $buffer .= qq{<b><font color="#ff0000">$OPTS{'message'}</font></b><br /><br />};
    }
    if ( $OPTS{'brute'} ) {
        $buffer .=
            "<h1>Brute Force Protection</h1>\n"
          . "This account is currently locked out because a <a href='http://en.wikipedia.org/wiki/Brute_force_attack'>brute force attempt</a> was detected.  Please wait a few minutes and try again.  Attempting to login again will only increase this delay.   "
          . ( $Cpanel::App::appname ne 'webmaild' ? "If you frequently experience this problem, we recommend having your username changed to something less generic.\n" : '' );
    }

    $OPTS{'frame_target'} &&= "target=\"$OPTS{'frame_target'}\"";

    if (
        open my $login_fh,
        '<',
        Cpanel::LoginTheme::getloginfile(
            'docname'    => 'login',
            'docext'     => 'html',
            'docroot'    => $cpconf->{'docroot'},
            'appname'    => $Cpanel::App::appname,
            'logintheme' => $logintheme
        )
    ) {
        local $/;
        my $login_html = readline $login_fh;
        close $login_fh;

        $login_html =~ s/\%login_theme\%/  Cpanel::Encoder::Tiny::safe_html_encode_str($logintheme)   /eg;
        $login_html =~ s/\%goto_uri\%/     Cpanel::Encoder::Tiny::safe_html_encode_str($OPTS{'goto_uri'})/eg;
        $login_html =~ s/\%frame_target\%/$OPTS{'frame_target'}/g;
        $login_html =~ s/\%MagicRevision\(([^\)]+)\)\%/Cpanel::MagicRevision::calculate_magic_url($1)/eg;
        $buffer .= $login_html;
    }

    if (
        !$OPTS{'brute'} && ( ( $cpconf->{'resetpass'} ne '0' || $cpconf->{'resetpass_sub'} ne '0' )
            && $Cpanel::App::appname eq 'cpaneld' )
        || (   $cpconf->{'resetpass_sub'} ne '0'
            && $Cpanel::App::appname eq 'webmaild' )
    ) {
        my $ruser                = Cpanel::Encoder::Tiny::safe_html_encode_str( $ENV{'REMOTE_USER'} // '' );
        my $html_safe_logintheme = Cpanel::Encoder::Tiny::safe_html_encode_str($logintheme);
        $buffer .= <<"EOM";
<br /><br />
<form action="/resetpass/">
<input type="hidden" name="login_theme" value="$html_safe_logintheme">
<table width="200" class="login">
    <tr>
        <td align="left" colspan="2"><b>Reset Password</b></td>
    </tr>
    <tr>
        <td>Username</td>
        <td><input type="text" name="user" size="16" value="$ruser"></td>
    </tr>
    <tr>
        <td align="center" colspan="2"><input class="input-button" type="submit" value="Reset"></form></td>
    </tr>
</table>
</form>
EOM
    }
    $buffer .= get_html_footer($logintheme);
    return ( 1, \$buffer );
}

sub fourohfour {
    my ( $socket, $logintheme, %OPTS ) = @_;
    my $buffer;
    if ( -e "$VAR_CPANEL_CPSRVD_DIR/fourohfour" ) {
        if ( open my $msg_fh, '<', "$VAR_CPANEL_CPSRVD_DIR/fourohfour" ) {
            local $/;
            my $message = readline($msg_fh);
            close $msg_fh;
            if ($message) {
                $buffer .= $message;
                return ( 1, \$buffer );
            }
        }
    }

    my $xss_safe_document = Cpanel::Encoder::Tiny::safe_html_encode_str( $OPTS{'document'} );
    my $VERSION           = Cpanel::Version::Full::getversion();
    $buffer .= <<"EOM";
<html>
<head>
<title>404 Not Found</title>
</head>
<body>
<h1>Not Found</h1>
<pre>
The server was not able to find the document ($xss_safe_document) you requested.
Please check the url and try again. You might also want to report this
error to your web hosting provider.
</pre>
<hr>
<address>$Cpanel::App::appname/$VERSION Server at $ENV{'HTTP_HOST'}</address>
</body>
</html>
EOM
    return ( 1, \$buffer );
}

sub accessdenied {
    my $buffer;
    if ( -e "$VAR_CPANEL_CPSRVD_DIR/accessdenied" ) {
        if ( open my $msg_fh, '<', "$VAR_CPANEL_CPSRVD_DIR/accessdenied" ) {
            local $/;
            my $message = readline($msg_fh);
            close $msg_fh;
            if ($message) {
                $buffer .= $message;
                return ( 1, \$buffer );
            }
        }
    }

    my $VERSION = Cpanel::Version::Full::getversion();
    $buffer .= <<"EOM";
<html>
<head>
<title>401 Access Denied</title>
</head>
<body>
<h1>Access Denied</h1>
<pre>
The server was configured to not permit you access to the specified resource.  If you believe this is in error or inadvertent, please contact the
system administrator and ask them to update the host access files.
</pre>
<hr>
<address>$Cpanel::App::appname/$VERSION Server at $ENV{'HTTP_HOST'}</address>
</body>
</html>
EOM
    return ( 1, \$buffer );
}

sub error503 {
    my ( $socket, $logintheme, %vars ) = @_;

    my $buffer;
    if ( -e "$VAR_CPANEL_CPSRVD_DIR/unavailable" ) {
        if ( open my $msg_fh, '<', "$VAR_CPANEL_CPSRVD_DIR/unavailable" ) {
            local $/;
            my $message = readline($msg_fh);
            close $msg_fh;
            if ($message) {
                $buffer .= $message;
                return ( 1, \$buffer );
            }
        }
    }

    $buffer .= <<"EOM";
<html>
<head>
<title>503 Service Unavailable</title>
</head>
<body>
<h1>The service is unavailable.</h1>
EOM

    if ( scalar keys %vars && defined $vars{page_message} ) {
        my $safe_page_message = Cpanel::Encoder::Tiny::safe_html_encode_str( $vars{page_message} );
        $buffer .= <<"EOM";
<p>
$safe_page_message
</p>
EOM
    }

    $buffer .= <<"EOM";
</body>
</html>
EOM

    return ( 1, \$buffer );
}

sub error400 {
    my ( $socket, $logintheme, %vars ) = @_;

    my $buffer;
    if ( -e "$VAR_CPANEL_CPSRVD_DIR/badrequest" ) {
        if ( open my $msg_fh, '<', "$VAR_CPANEL_CPSRVD_DIR/badrequest" ) {
            local $/;
            my $message = readline($msg_fh);
            close $msg_fh;
            if ($message) {
                $buffer .= $message;
                return ( 1, \$buffer );
            }
        }
    }

    $buffer .= <<"EOM";
<html>
<head>
<title>400 Bad Request</title>
</head>
<body>
<h1>Your client sent a request that the server could not understand.</h1>
EOM

    if ( scalar keys %vars && defined $vars{page_message} ) {
        my $safe_page_message = Cpanel::Encoder::Tiny::safe_html_encode_str( $vars{page_message} );
        $buffer .= <<"EOM";
<p>
$safe_page_message
</p>
EOM
    }

    $buffer .= <<"EOM";
</body>
</html>
EOM

    return ( 1, \$buffer );
}

sub phpsessionerror {

    my $buffer;
    if ( -e "$VAR_CPANEL_CPSRVD_DIR/phpsessionerror" ) {
        if ( open my $msg_fh, '<', "$VAR_CPANEL_CPSRVD_DIR/phpsessionerror" ) {
            local $/;
            my $message = readline($msg_fh);
            close $msg_fh;
            if ($message) {
                $buffer .= $message;
                return ( 1, \$buffer );
            }
        }
    }

    my $VERSION = Cpanel::Version::Full::getversion();
    $buffer .= <<"EOM";
<html>
<head>
<title>401 Access Denied</title>
</head>
<body>
<h1>Access Denied</h1>
<pre>
Unable to establish a PHP session.

The account must be able to write to the php session directory and must not exceed the assigned disk quota.

If you believe that this is in error or inadvertent, contact your system administrator and ask them to review your server settings.
</pre>
<hr>
<address>$Cpanel::App::appname/$VERSION Server at $ENV{'HTTP_HOST'}</address>
</body>
</html>
EOM
    return ( 1, \$buffer );
}

sub referrer_denied {
    my ( $socket, $logintheme, %OPTS ) = @_;

    my $buffer;
    my $templatefile;
    if ( -e "$VAR_CPANEL_CPSRVD_DIR/referrerdenied" && !-z _ ) {
        $templatefile = "$VAR_CPANEL_CPSRVD_DIR/referrerdenied";
    }
    elsif ( -e '/usr/local/cpanel/etc/cpsrvd/referrerdenied' && !-z _ ) {
        $templatefile = '/usr/local/cpanel/etc/cpsrvd/referrerdenied';
    }

    if ($templatefile) {
        if ( open my $msg_fh, '<', $templatefile ) {
            my $html_safe_uri      = Cpanel::Encoder::Tiny::safe_html_encode_str( $OPTS{'uri'} );
            my $html_safe_referrer = Cpanel::Encoder::Tiny::safe_html_encode_str( $ENV{'HTTP_REFERER'} );
            while ( readline($msg_fh) ) {

                if (/\%([^\%]+)\%/) {
                    my $var = $1;
                    if ( $var eq 'tableized_form' ) {
                        $buffer .= encode_form( $OPTS{'form_ref'}, 'table' );
                        next;
                    }
                    elsif ( $var eq 'htmlized_form' ) {
                        $buffer .= encode_form( $OPTS{'form_ref'}, 'html' );
                        next;
                    }
                    elsif ( $var eq 'referrer' ) {
                        s/%referrer%/$html_safe_referrer/g;
                    }
                    elsif ( $var eq 'uri' ) {
                        s/%uri%/$html_safe_uri/g;
                    }
                }
                $buffer .= $_;
            }
            close($msg_fh);
        }
    }
    else {
        my $VERSION = Cpanel::Version::Full::getversion();
        $buffer .= <<"EOM";
<html>
<head>
<title>401 Access Denied</title>
</head>
<body>
<h1>Access Denied</h1>
<p>The referring site is not authorized (direct linking is not allowed). This page must be accessed from the control panel.</p>
<hr>
<address>$Cpanel::App::appname/$VERSION Server at $ENV{'HTTP_HOST'}</address>
</body>
</html>
EOM
    }
    return ( 1, \$buffer );
}

sub token_denied {
    my ( $socket, $logintheme, %OPTS ) = @_;

    my $buffer;
    my $templatefile;
    if ( -e "$VAR_CPANEL_CPSRVD_DIR/tokendenied" && !-z _ ) {
        $templatefile = "$VAR_CPANEL_CPSRVD_DIR/tokendenied";
    }
    elsif ( -e '/usr/local/cpanel/etc/cpsrvd/tokendenied' && !-z _ ) {
        $templatefile = '/usr/local/cpanel/etc/cpsrvd/tokendenied';
    }
    if ($templatefile) {
        my $output = '';
        if ( open my $msg_fh, '<', $templatefile ) {
            my $html_safe_uri      = Cpanel::Encoder::Tiny::safe_html_encode_str( $OPTS{'goto_uri'} );
            my $html_safe_user     = Cpanel::Encoder::Tiny::safe_html_encode_str( $OPTS{'user'} );
            my $html_safe_referrer = Cpanel::Encoder::Tiny::safe_html_encode_str( $ENV{'HTTP_REFERER'} );
            my $html_safe_theme    = Cpanel::Encoder::Tiny::safe_html_encode_str( $OPTS{'theme'} );
            my $html_safe_msg      = Cpanel::Encoder::Tiny::safe_html_encode_str( $OPTS{'msg'} );
            my $parameterized_form = $OPTS{'parameterized_form'};
            while ( readline($msg_fh) ) {

                if (/\%([^\%]+)\%/) {
                    my $var = $1;
                    if ( $var eq 'tableized_form' ) {
                        $output .= encode_form( $OPTS{'form_ref'}, 'table' );
                        next;
                    }
                    elsif ( $var eq 'parameterized_form' ) {
                        s/%parameterized_form%/$parameterized_form/g;
                    }
                    elsif ( $var eq 'referrer' ) {
                        s/%referrer%/$html_safe_referrer/g;
                    }
                    elsif ( $var eq 'uri' ) {
                        s/%uri%/$html_safe_uri/g;
                    }
                    elsif ( $var eq 'error_msg' ) {
                        s/%error_msg%/$html_safe_msg/g;
                    }
                    elsif ( $var eq 'user' ) {
                        s/%user%/$html_safe_user/g;
                    }
                    elsif ( $var eq 'theme' ) {
                        s/%theme%/$html_safe_theme/g;
                    }
                }
                $output .= $_;
            }
            close($msg_fh);
        }
        $buffer .= $output;    #one ssl write
    }
    else {
        my $VERSION = Cpanel::Version::Full::getversion();
        $buffer .= <<"EOM";
<html>
<head>
<title>401 Access Denied</title>
</head>
<body>
<h1>Access Denied: Security Token Failure</h1>
<p>Security token checks have failed for the requested resource.  This page must be accessed from the control panel.</p>
<hr>
<address>$Cpanel::App::appname/$VERSION Server at $ENV{'HTTP_HOST'}</address>
</body>
</html>
EOM
    }
    return ( 1, \$buffer );
}

sub token_passthrough {
    my ( $socket, $logintheme, %OPTS ) = @_;
    my $templatefile;

    my $buffer;
    if ( -e "$VAR_CPANEL_CPSRVD_DIR/tokendpassthrough" && !-z _ ) {
        $templatefile = "$VAR_CPANEL_CPSRVD_DIR/tokenpassthrough";
    }
    elsif ( -e '/usr/local/cpanel/etc/cpsrvd/tokenpassthrough' && !-z _ ) {
        $templatefile = '/usr/local/cpanel/etc/cpsrvd/tokenpassthrough';
    }
    else {

    }

    if ( $templatefile && open my $msg_fh, '<', $templatefile ) {
        my $html_safe_uri = Cpanel::Encoder::Tiny::safe_html_encode_str( $OPTS{'goto_uri'} );
        my $output        = q{};
        while ( readline $msg_fh ) {

            if (/\%([^\%]+)\%/) {
                my $var = $1;
                if ( $var eq 'htmlized_form' ) {
                    $output .= encode_form( $OPTS{'form_ref'}, 'html' );
                    next;
                }
                elsif ( $var eq 'uri' ) {
                    s/%uri%/$html_safe_uri/g;
                }
                elsif ( $var eq 'security_token' ) {
                    s/%security_token%/$main::security_token/g;
                }
            }
            $output .= $_;
        }
        close $msg_fh;
        $buffer .= $output;
    }
    else {
        my $VERSION = Cpanel::Version::Full::getversion();
        $buffer .= <<"EOM";
<html>
<head>
<title>Passthrough template missing</title>
</head>
<body>
<h1>Passthrough template missing</h1>
<p>Your request could not be completed because the security token passthrough template is missing on this system.</p>
<hr>
<address>$Cpanel::App::appname/$VERSION Server at $ENV{'HTTP_HOST'}</address>
</body>
</html>
EOM
    }
    return ( 1, \$buffer );
}

sub license_status {
    my ( $socket, $logintheme, %OPTS ) = @_;

    my $buffer;
    $buffer .= get_html_header($logintheme);

    $buffer .= "<h1>License Status</h1>\n";

    my $license_status = $OPTS{'license_status'} // [];
    for ( my $i = 0; $i < scalar @$license_status; $i += 2 ) {
        my $k = $license_status->[$i] or last;
        my $v = $license_status->[ $i + 1 ] // '';

        $buffer .= $k . ": " . $v . "<br />\n";
    }

    if ( !$OPTS{'current_time'} ) {
        $buffer .= "Current Time: (License File Invalid)<br>\n";
    }
    else {
        $buffer .= "Current Time: $OPTS{'local_time'}<br>\n";
    }
    $buffer .= "Seconds Left on License: $OPTS{'seconds_left'}<br />\n<br />\n<a href=\"showlicensehistory\">Show License History</a><br />\n";
    $buffer .= get_html_footer($logintheme);
    return ( 1, \$buffer );
}

sub license_history {
    my ( $socket, $logintheme, %OPTS ) = @_;

    my %status_codes = (
        0 => 'Not Yet Active',
        1 => 'Active',
        2 => 'Expired',
    );

    my $buffer;
    $buffer .= get_html_header($logintheme);
    $buffer .= <<EOM;
<h1>License History</h1>
<table>
<tr>
    <th>IP</th>
    <th>Package</th>
    <th>Licensee</th>
    <th>Group</th>
    <th>Active date</th>
    <th>Status</th>
</tr>
EOM
    foreach my $license ( @{ $OPTS{'licenses'} } ) {
        foreach my $row ( $license->{'attributes'}->@*, $license->{'history'}->@* ) {
            my ( $ip, $pkg, $company, $group, $date, $status ) = map { Cpanel::Encoder::Tiny::safe_html_encode_str($_) } (
                $license->{'ip'},
                $row->@{qw/package company group adddate/},
                $status_codes{ $row->{'status'} } // '?',
            );
            $buffer .= <<EOM;
<tr>
    <td>$ip</td>
    <td>$pkg</td>
    <td>$company</td>
    <td>$group</td>
    <td>$date</td>
    <td>$status</td>
</tr>
EOM
        }
    }
    $buffer .= "</table>\n";
    $buffer .= get_html_footer($logintheme);
    return ( 1, \$buffer );
}

sub _process_old_template_file {
    my ( $filetoslurp, %OPTS ) = @_;

    open( my $slurp_file, '<', $filetoslurp ) or do {
        warn "open($filetoslurp): $!" if $! != _ENOENT();
        return undef;
    };

    local $/;
    my $data = readline($slurp_file);

    if ( index( $data, '%' ) > -1 ) {
        foreach my $opt ( keys %OPTS ) {
            $data =~ s/\%\Q$opt\E\%/$OPTS{$opt}/g;
        }
        $data =~ s/\%MagicRevision\(([^\)]+)\)\%/Cpanel::MagicRevision::calculate_magic_url($1)/eg;
    }

    close($slurp_file);

    return $data;
}

sub _trial_banner {
    my ($opts_hr) = @_;
    my $banner = '';

    if ( $opts_hr->{'_is_trial'} ) {    # The lack of localization is intentional
        $banner = '<div style="padding: 5px 15px 5px 25px; background-color: #d7edf9; border: 1px solid #179bd7; width: 175px; margin: 0 auto; border-radius: 2px; font-weight: bolder">This server uses a trial license</div>';
    }
    return $banner;
}

1;
