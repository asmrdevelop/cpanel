package Cpanel::Email::PasswdPop;

# cpanel - Cpanel/Email/PasswdPop.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::Auth::Generate       ();
use Cpanel::SafeFile             ();
use Cpanel::PwCache              ();
use Cpanel::Logger               ();
use Cpanel::FileUtils::TouchFile ();
use Cpanel::AdminBin::Call       ();

my $logger = Cpanel::Logger->new();

sub passwd {
    my %OPTS = @_;

    if ( !$OPTS{'virtualuser'} ) {
        return ( 0, 'Virtual username must be provided.' );
    }

    if ( !$OPTS{'new_password'} ) {
        return ( 0, 'New password must be provided.' );
    }

    my $homedir = $OPTS{'homedir'};
    if ( !$homedir ) {
        $homedir = Cpanel::PwCache::gethomedir( $OPTS{'system_user'} );
    }
    if ( !$homedir ) {
        return ( 0, 'homedir must be provided.' );
    }
    $homedir =~ /(.*)/;
    $homedir = $1;

    my $domain = $OPTS{'domain'};
    $domain =~ /(.*)/;
    $domain = $1;
    $domain =~ s/\///g;
    if ( !$domain ) {
        return ( 0, 'domain must be provided.' );
    }

    my $virtualuser = $OPTS{'virtualuser'};
    $virtualuser =~ /(.*)/;
    $virtualuser = $1;
    $virtualuser =~ s/\///g;

    my $cpass;
    while ( !$cpass || $cpass =~ /:/ ) {
        $cpass = Cpanel::Auth::Generate::generate_password_hash( $OPTS{'new_password'} );
    }

    my $mytime = int( time / ( 60 * 60 * 24 ) );
    if ( !-e "$homedir/etc/$domain/shadow" ) { Cpanel::FileUtils::TouchFile::touchfile("$homedir/etc/$domain/shadow") or $logger->die("Could not create $homedir/etc/$domain/shadow"); }
    my $pwlock = Cpanel::SafeFile::safeopen( \*PW, '+<', $homedir . '/etc/' . $domain . '/shadow' );
    if ( !$pwlock ) {
        $logger->warn("Could not edit $homedir/etc/$domain/shadow");
        return;
    }
    my @PW = <PW>;
    seek( PW, 0, 0 );
    while ( my $line = shift(@PW) ) {
        if ( $line =~ /^\Q$virtualuser\E\:/ ) {
            print PW $virtualuser . ':' . $cpass . ':' . $mytime . '::::::' . "\n";
        }
        else {
            print PW $line;
        }
    }
    truncate( PW, tell(PW) );
    Cpanel::SafeFile::safeclose( \*PW, $pwlock );

    Cpanel::AdminBin::Call::call(
        'Cpanel',
        'mail',
        'CLEAR_AUTH_CACHE',
        "$virtualuser\@$domain"
    );

    return ( 1, 'Password changed' );
}

1;
