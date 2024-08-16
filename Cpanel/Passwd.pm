package Cpanel::Passwd;

# cpanel - Cpanel/Passwd.pm                        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::LoadModule         ();
use Cpanel::Encoder::Tiny      ();
use Cpanel::Locale             ();
use Cpanel::Reseller::Override ();

our $VERSION = '1.5';

my $locale;

sub api2_set_digest_auth {
    my %OPTS = @_;

    $locale ||= Cpanel::Locale->get_handle();
    my $user         = $Cpanel::user;
    my $password     = $OPTS{'password'} || ( Cpanel::Reseller::Override::is_overriding() ? '' : $Cpanel::userpass );    #TEMP_SESSION_SAFE
    my $enabledigest = exists $OPTS{'digestauth'} ? $OPTS{'digestauth'} : $OPTS{'enabledigest'};

    if ( !defined $enabledigest ) {
        return [ { 'result' => 0, 'reason' => $locale->maketext( 'The “[_1]” parameter is required.', 'enabledigest' ) } ];
    }

    Cpanel::LoadModule::load_perl_module('Cpanel::AdminBin');
    my $results = Cpanel::AdminBin::adminfetchnocache( 'security', '', 'SETDIGESTAUTH', undef, { 'user' => $user, 'password' => $password, 'enabledigest' => $enabledigest } );

    if ( !$results || !ref $results->[2] ) {
        $Cpanel::CPERROR{$Cpanel::context} = $locale->maketext('Failed to get a valid result from [output,class,securityadmin,code] while requesting [output,class,SETDIGESTAUTH,code].');
        return;
    }

    return [ $results->[2] ];
}

sub api2_change_password {
    my %CFG = @_;

    for my $key ( 'oldpass', 'newpass' ) {
        if ( !exists $CFG{$key} || !defined $CFG{$key} ) {
            $Cpanel::CPERROR{'passwd'} = qq("$key" is a required argument.);
            return [
                {
                    'passwdoutput' => undef,
                    'applist'      => [ { 'app' => 'none' } ],
                    'status'       => 0,
                    'statustxt'    => $Cpanel::CPERROR{'passwd'}
                }
            ];
        }
    }

    ## investigates CFG{'enabledigest'}, and the current state of the user in /etc/digestshadow
    Cpanel::LoadModule::load_perl_module('Cpanel::ChangePasswd');
    my $digest_auth = Cpanel::ChangePasswd::get_digest_auth_option( \%CFG, $Cpanel::user );

    my ( $status, $result, $passwdtxt, $rclist ) = _change_password( $CFG{'oldpass'}, $CFG{'newpass'}, $CFG{'enablemysql'}, $digest_auth );
    if ( !$status ) { $Cpanel::CPERROR{'passwd'} = $result; }
    if ( !$rclist ) { $rclist = [ { 'app' => 'none' } ]; }
    my $rsd = [ { 'status' => $status, 'statustxt' => $result, 'passwdoutput' => $passwdtxt, 'applist' => $rclist } ];
    $Cpanel::CPVAR{'change_password_status'} = $status;
    if ($status) {

        # sysuser, user, homedir
        Cpanel::LoadModule::load_perl_module('Cpanel::ForcePassword::Unforce');
        Cpanel::ForcePassword::Unforce::unforce_password_change( $Cpanel::user, $Cpanel::user, $Cpanel::homedir );
    }
    return $rsd;
}

## NOTE: suspect deprecation. I do not believe this is used any longer.
sub change_password {
    my ( $status, $result, $passwdtxt, $rclist ) = _change_password(@_);
    if ( !$status ) { $Cpanel::CPERROR{'passwd'} = $result; }
    if ( !$rclist ) { $rclist = [ { 'app' => 'none' } ]; }
    $Cpanel::CPVAR{'change_password_status'} = $status;

    ## case 30334: removed explicit call to ::EventHandler subsystem

    my $js = '';

    if ($status) {
        $js = qq{
            <script>
                function SetCookie(name, value, expires, path)
                {
                    document.cookie = name + "=" + escape (value) +
                        ((expires) ?    ("; expires=" + expires.toLocaleString()) : "") +        ((path) ?       ("; path=" + path) : "");
                }
            SetCookie('cpsession','closed',null,'/');
            </script>
        };
    }
    return $js . Cpanel::Encoder::Tiny::safe_html_encode_str($result);
}

sub _change_password {
    my ( $oldpass, $newpass, $enablemysql, $enabledigest ) = @_;
    $locale ||= Cpanel::Locale->get_handle();

    if ( !main::hasfeature("password") ) {
        return ( 0, $locale->maketext('This feature is not enabled.') );
    }
    if ( $Cpanel::CPDATA{'DEMO'} eq "1" ) {
        return ( 0, $locale->maketext('Sorry the password cannot be changed in this demo.') );
    }
    Cpanel::LoadModule::load_perl_module('Cpanel::ChangePasswd');
    return Cpanel::ChangePasswd::change_password(
        'current_password'  => $oldpass,
        'new_password'      => $newpass,
        'user'              => $Cpanel::user,
        'optional_services' => { 'mysql' => $enablemysql, 'digest' => $enabledigest },
        'ip'                => $ENV{'REMOTE_ADDR'},
        'origin'            => 'cpanel',
        'initiator'         => $Cpanel::user,
    );
}

my $xss_checked_modify_none_allow_demo = {
    modify      => 'none',
    xss_checked => 1,
    allow_demo  => 1,
};

our %API = (
    change_password => $xss_checked_modify_none_allow_demo,
    set_digest_auth => $xss_checked_modify_none_allow_demo,
);

sub api2 {
    my ($func) = @_;
    return { %{ $API{$func} } } if $API{$func};
    return;
}

1;
