package Cpanel::TailWatch::Utils::Status;

# cpanel - Cpanel/TailWatch/Utils/Status.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

sub Cpanel::TailWatch::status {
    my ($self) = @_;

    my $abled = $self->tailwatchd_is_disabled() ? 'disabled' : 'enabled';
    print "tailwatchd is $abled\n";    # '[_1]' is currently [truefalse,_2,enabled,disabled]

    my $curpid = $self->get_pid_from_pidfile();
    if ($curpid) {
        if ( kill 'ZERO', $curpid ) {
            print "Running, PID $curpid\n";
        }
        else {
            print "Not running\n";
        }
    }
    else {
        print "Not running\n";
    }

    for my $en ( @{ $self->{'enabled_modules'} } ) {
        print "  Driver (Active: $en->[1]) $en->[0]\n";
    }
}

1;
