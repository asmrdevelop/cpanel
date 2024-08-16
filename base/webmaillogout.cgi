#!/usr/local/cpanel/3rdparty/bin/perl

use strict;
use Cpanel::Encoder::Tiny ();
my $html_safe_login_theme = Cpanel::Encoder::Tiny::safe_html_encode_str( $ENV{'LOGIN_THEME'} );

print <<EOM;
<center>
<h2>You have been logged out.</h2>
<br>
<form action=/login/ method=POST><a href="/">Login Again</a><br><br><b>or</b><br><br> Username: <input
type=text name=user size=16> Password: <input type=password name=pass size=16> <input type=submit value="Login">.
<input type="hidden" name="theme" value="$html_safe_login_theme">
</form>
</center>
EOM
