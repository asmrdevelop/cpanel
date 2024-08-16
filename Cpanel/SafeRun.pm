package Cpanel::SafeRun;

# cpanel - Cpanel/SafeRun.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Carp                      ();
use Cpanel::FindBin           ();
use Cpanel::SafeRun::Simple   ();
use Cpanel::SafeRun::Errors   ();
use Cpanel::SafeRun::FDs      ();
use Cpanel::SafeRun::BG       ();
use Cpanel::SafeRun::Env      ();
use Cpanel::SafeRun::Timed    ();
use Cpanel::SafeRun::Dynamic  ();
use Cpanel::Sys::Setsid::Fast ();

our $VERSION = '1.6';

*saferunallerrors      = *Cpanel::SafeRun::Errors::saferunallerrors;
*saferunnoerror        = *Cpanel::SafeRun::Errors::saferunnoerror;
*saferundynamic        = *Cpanel::SafeRun::Dynamic::saferundynamic;
*livesaferun           = *Cpanel::SafeRun::Dynamic::livesaferun;
*saferunnoerrordynamic = *Cpanel::SafeRun::Dynamic::saferunnoerrordynamic;
*saferun_r_cleanenv    = *Cpanel::SafeRun::Env::saferun_r_cleanenv;
*saferun_cleanenv2     = *Cpanel::SafeRun::Env::saferun_cleanenv2;
*saferun_r             = *Cpanel::SafeRun::Simple::saferun_r;
*saferun               = *Cpanel::SafeRun::Simple::saferun;
*timedsaferun          = *Cpanel::SafeRun::Timed::timedsaferun;
*findbin               = *Cpanel::FindBin::findbin;
*find_bin              = *findbin;
*nooutputsystembg      = *Cpanel::SafeRun::BG::nooutputsystembg;
*setupchildfds         = *Cpanel::SafeRun::FDs::setupchildfds;
*closefds              = *Cpanel::SafeRun::FDs::closefds;

#same as bgrun but it will still display output to stdout
sub visbgrun {
    my $opts = { 'cmd' => \@_, 'vis' => 1 };
    return _bgrun($opts);
}

sub bgrun {
    my $opts = { 'cmd' => \@_ };
    return _bgrun($opts);
}

sub _bgrun {
    my $opts = shift;
    my @cmd  = @{ $opts->{'cmd'} };
    my $vis  = $opts->{'vis'} ? 1 : 0;
    if ( my $pid = fork() ) {
        if ($vis) {
            while ( waitpid( $pid, 1 ) != -1 ) {
                sleep(1);
            }
        }
        return 1;
    }
    else {
        # Start a new process group and detach from any tty's.
        Cpanel::Sys::Setsid::Fast::fast_setsid();

        if ($vis) {
            open( STDIN, '<', '/dev/null' );
            open( STDERR, ">&STDOUT" );
            closefds();
            $SIG{'PIPE'} = 'IGNORE';
        }
        else {
            setupchildfds();
        }
        exec(@cmd) or do {
            warn "Unable to exec command: " . join( ' ', @cmd );
            exit 1;
        };
    }
    return 0;
}

1;
