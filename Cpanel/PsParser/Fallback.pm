package Cpanel::PsParser::Fallback;

# cpanel - Cpanel/PsParser/Fallback.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::SafeRun::Object ();
use Cpanel::Exception       ();
use Cpanel::Debug           ();
use Try::Tiny;

sub parse_ps {
    my (%OPTS)       = @_;
    my $exclude_self = $OPTS{'exclude_self'};
    my $want_uid     = $OPTS{'want_uid'};
    my ( $ps_run, $err );
    try {
        local $ENV{'TERM'} = 'dumb';
        $ps_run = Cpanel::SafeRun::Object->new(
            'program' => '/bin/ps',
            'args'    => [ '-ewwo', 'pid,uid,user,nice,pmem,pcpu,etime,state,command' ],
        );
    }
    catch {
        $err = Cpanel::Exception::get_string($_);
    };
    if ($err) {
        Cpanel::Debug::log_warn( 'Failed to retrieve process list: ' . $err );
        return;
    }

    my ( @PS, $pid, $uid, $user, $nice, $mem, $cpu, $etime, $state, $command );
    my $current_pid = $$;
    my $child_pid   = $ps_run->child_pid();
    foreach my $line ( split( m{\n}, $ps_run->stdout() ) ) {

        next if ( !length( ( ( $pid, $uid, $user, $nice, $mem, $cpu, $etime, $state, $command ) = parse_ps_line($line) )[0] ) );
        if ( $exclude_self && ( $pid == $child_pid || $pid == $current_pid ) ) { next; }
        $command =~ s/\s+\z//s;    # Strip any trailing whitespace from command and will "chomp" newlines if any

        if ( $etime =~ m{^([0-9]+)-([0-9]+):([0-9]+):([0-9]+)$} ) {
            my ( $days, $hours, $minutes, $seconds ) = ( $1, $2, $3, $4 );
            $etime = ( $days * 86400 ) + ( $hours * 3600 ) + ( $minutes * 60 ) + ($seconds);
        }
        elsif ( $etime =~ m{^([0-9]+):([0-9]+):([0-9]+)$} ) {
            my ( $hours, $minutes, $seconds ) = ( $1, $2, $3 );
            $etime = ( $hours * 3600 ) + ( $minutes * 60 ) + ($seconds);
        }

        next if ( defined $want_uid && $uid != $want_uid );    #

        push @PS,
          {
            'pid'     => $pid,
            'user'    => $user,
            'uid'     => $uid,
            'nice'    => $nice,
            'mem'     => $mem,
            'cpu'     => $cpu,
            'elapsed' => $etime,
            'state'   => $state,
            'command' => $command
          };
    }
    if ( !@PS && !length $ps_run->stdout() ) {
        Cpanel::Debug::log_warn('Failed to retrieve process list using /bin/ps');
        return;
    }
    return \@PS;
}

sub parse_ps_line {
    return ( $_[0] =~ m/^\s*(\d+)\s+(\d+)\s+(\S+)\s+([\d+-]+)\s+([\d\.%]+)\s+([\d\.%]+)\s+([\d:-]+)\s+(.)\s+(.+)$/ );
}

1;
