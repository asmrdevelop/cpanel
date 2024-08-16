package Cpanel::Cgi;

# cpanel - Cpanel/Cgi.pm                           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel                 ();
use Cpanel::Logs::Find     ();
use Cpanel::Encoder::Tiny  ();
use Cpanel::Binaries       ();
use Cpanel::AdminBin::Call ();

my $cached_php_path;

our ( @ISA, @EXPORT, $VERSION );
$VERSION = '1.0';

sub _create_temp_user_if_needed {
    if ( $ENV{'SESSION_TEMP_USER'} ) {

        # TODO: Create a UAPI function that seperates out this functionality
        # that will report errors.  This must remain here for legacy compat
        Cpanel::AdminBin::Call::call( 'Cpanel', 'session_call', 'SETUP_TEMP_SESSION', { 'session_temp_user' => $ENV{'SESSION_TEMP_USER'} } );
    }
}

sub phpmyadminlink {
    _create_temp_user_if_needed();

    # We now create temp users for mysql
    # when they login without the user/pass
    # combination for the cPanel account
    return $ENV{'cp_security_token'} . '/3rdparty/phpMyAdmin/index.php';
}

sub phppgadminlink {

    _create_temp_user_if_needed();

    # We now create temp users for mysql
    # when they login without the user/pass
    # combination for the cPanel account
    return $ENV{'cp_security_token'} . '/3rdparty/phpPgAdmin/index.php';
}

sub accessloglink {

    my ( $mday, $mon, $year );
    ( undef, undef, undef, $mday, $mon, $year, undef, undef, undef )

      = localtime( time() );

    $mon++;
    $year += 1900;

    return "$ENV{'cp_security_token'}/getaccesslog/accesslog-$Cpanel::CPDATA{'DNS'}-$mon-$mday-$year.gz";
}

sub accessloglinks {

    my ( $mday, $mon, $year );
    ( undef, undef, undef, $mday, $mon, $year, undef, undef, undef )

      = localtime( time() );

    $mon++;
    $year += 1900;

    foreach my $domain (@Cpanel::DOMAINS) {
        if ( Cpanel::Logs::Find::find_wwwaccesslog($domain) eq "" ) { next(); }
        print "<a href=\"$ENV{'cp_security_token'}/getaccesslog/accesslog_${domain}_${mon}_${mday}_${year}.gz\">${domain}</a><br>\n";
    }
}

sub backuplink {
    my ( $mday, $mon, $year );
    ( undef, undef, undef, $mday, $mon, $year, undef, undef, undef ) = localtime( time() );
    $mon++;
    $year += 1900;
    return "$ENV{'cp_security_token'}/getbackup/backup-$Cpanel::CPDATA{'DNS'}-$mon-$mday-$year.tar.gz";
}

sub mkclock {
    my ($html) = @_;

    # Dummy output.
    my $acode = '<span/>';

    return Cpanel::Encoder::Tiny::safe_html_encode_str($acode) if $html == 1;
    return $acode;
}

sub mkcountdown {
    my ($html) = @_;

    # Dummy output.
    my $acode = '<span/>';

    return Cpanel::Encoder::Tiny::safe_html_encode_str($acode) if $html == 1;
    return $acode;
}

sub sanitize_counter_name {
    my $name = shift;

    $name =~ s/[^a-zA-Z0-9]//g if defined $name;

    return $name;
}

sub cleanenv {
    foreach my $env ( sort keys %ENV ) {
        if ( $env ne "PATH" ) {
            delete $ENV{$env};
        }
    }
}

sub convertphpbbtoaddon {
    return if ( !-e "$Cpanel::homedir/.xmbs" );
    open( XMBS,  "<",  "$Cpanel::homedir/.xmbs" );
    open( PHPBB, ">>", "$Cpanel::homedir/.addonscgi-phpBB" );
    while (<XMBS>) {
        print PHPBB;
    }
    close(PHPBB);
    close(XMBS);
    unlink("$Cpanel::homedir/.xmbs");
    return "";
}

sub convertagbookstoaddon {
    return if ( !-e "$Cpanel::homedir/.agbooks" );
    open( XMBS,  "<",  "$Cpanel::homedir/.agbooks" );
    open( PHPBB, ">>", "$Cpanel::homedir/.addonscgi-AdvancedGuestBook" );
    while (<XMBS>) {
        print PHPBB;
    }
    close(PHPBB);
    close(XMBS);
    unlink("$Cpanel::homedir/.agbooks");
    return "";
}

sub _get_php_path {
    $cached_php_path ||= Cpanel::Binaries::path('php-cgi');
    return $cached_php_path;
}

1;
