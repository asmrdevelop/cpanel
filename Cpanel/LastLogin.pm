package Cpanel::LastLogin;

# cpanel - Cpanel/LastLogin.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Cpanel::Locale             ();
use Cpanel::LastLogin::Tiny    ();
use Cpanel::Reseller::Override ();

my $locale;

sub LastLogin_init { return 1; }

sub LastLogin_lastlogin {
    my $loginip = lastlogin();
    if ($loginip) { print $loginip; }
}

sub LastLogin_set_lastlogin_cpvar {
    my ($default) = @_;
    $Cpanel::CPVAR{'lastlogin'} = Cpanel::LastLogin::Tiny::lastlogin() || $default || '';
}

sub lastlogin {
    my $lastlogin = Cpanel::LastLogin::Tiny::lastlogin();
    if ( !$lastlogin ) {
        $locale ||= Cpanel::Locale->get_handle();
        return $locale->maketext('None Recorded');
    }
    return $lastlogin;
}

sub passwarning {
    $locale ||= Cpanel::Locale->get_handle();
    if ( Cpanel::Reseller::Override::is_overriding() ) {    #TEMP_SESSION_SAFE
        my $reseller_login_warning_text = $locale->maketext('[output,em,WARNING]: You logged in with the reseller or [asis,root] password.');
        return qq{<br /><div align="center"><b><font color="#FF0000">$reseller_login_warning_text</font></b></div>};
    }
    return '';
}

1;
