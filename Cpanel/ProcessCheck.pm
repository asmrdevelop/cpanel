package Cpanel::ProcessCheck;

# cpanel - Cpanel/ProcessCheck.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

### DO NOT USE THIS MODULE IN NEW CODE
### USE  Cpanel::ProcessCheck::Running instead
### DO NOT USE THIS MODULE IN NEW CODE

use strict;
our $VERSION = '0.1';

# ez way to provide unit test for previouspids
sub _do_ps {
    return `ps uxawwwwwww`;
}

### DO NOT USE THIS MODULE IN NEW CODE
### USE  Cpanel::ProcessCheck::Running instead
### DO NOT USE THIS MODULE IN NEW CODE
sub previouspids {
    my %AGS    = @_;
    my $search = $AGS{process} || return;

    my $searchtunes = [];
    $searchtunes = ref $AGS{processarg} eq 'ARRAY' ? $AGS{processarg} : [ $AGS{processarg} ] if defined $AGS{processarg};

    my $parent_pid = getppid();
    my $isrunning  = _do_ps();

    my @PS = split( /\n/, $isrunning );
    @PS = grep( /$search/, @PS );
    return if ( $#PS == -1 );

    foreach my $tune (@$searchtunes) {
        @PS = grep( /$tune/, @PS );
    }

    @PS = grep( !/(?:restartsrv|defunct|zombie|\/rc\.d\/|\/init\.d\/)/, @PS );
    my %PIDS;
    foreach my $ps (@PS) {
        $ps =~ /\D+\s+(\d+)/;
        my $pid = $1;
        $PIDS{$pid} = 1;
    }
    delete $PIDS{$parent_pid};
    delete $PIDS{$$};

    return %PIDS;
}

1;
