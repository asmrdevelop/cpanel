package Cpanel::Sys::Kill;

# cpanel - Cpanel/Sys/Kill.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::AccessIds::SetUids ();
use Cpanel::ForkAsync          ();
use Cpanel::PwCache            ();
use Cpanel::TimeHiRes          ();
use Cpanel::PsParser           ();
use Cpanel::Wait::Constants    ();
use Cpanel::Waitpid            ();

our $MAX_ATTEMPTS_TO_KILL_PROCS = 25;

=pod

=encoding utf-8

=head1 NAME

Cpanel::Sys::Kill  - Terminate proceses owned by a user

=head1 SYNOPSIS

    # Aggressive (account removal)
    Cpanel::Sys::Kill::kill_pids_owned_by( 'bob', 'KILL' );

    # Nice (give them some type to shutdown)
    Cpanel::Sys::Kill::kill_users_processes( 'bob' );


=head2 kill_pids_owned_by($user, $signal)

Calls appropriate system command for signaling a user's process.

Signal defaults to -15 (TERM)

Returns 1 if the pids were killed

Returns 0 if the pids were not killed

=cut

sub kill_pids_owned_by {
    my ( $user, $signal ) = @_;
    $signal ||= 'TERM';    # default to TERM like everything else
    $signal =~ s/^-//;

    my ( $uid, $gid );

    # do one single user / id resolution
    # we could also use the fast_parse_ps resolve_uids option,
    #   but this will be slower as we will need to get username for all process
    if ( $user =~ m{^[0-9]+$} ) {
        $uid = $user;
    }
    else {
        ( $uid, $gid ) = ( Cpanel::PwCache::getpwnam($user) )[ 2, 3 ];
    }

    # make sure uid is defined and non-root
    return 0 unless $uid;

    my $is_kill_signal = ( $signal eq 'KILL' || $signal eq '9' ) ? 1 : 0;

    # We need to do this a few times see COBRA-3083
    foreach ( 1 .. $MAX_ATTEMPTS_TO_KILL_PROCS ) {
        my $procs           = _procs_for_uid($uid);
        my @non_zombie_pids = map { $_->{'pid'} } grep { $_->{'state'} ne 'Z' } @$procs;
        if (@non_zombie_pids) {
            if ( !defined $gid ) {
                $gid = ( Cpanel::PwCache::getpwuid($uid) )[3];
            }

            # To be safe we make sure we only kill processes the user owns.
            # We must use a method of dropping privileges that forks or we
            # will bring down every process root owns except init.
            my $pid = Cpanel::ForkAsync::do_in_child(
                sub {
                    Cpanel::AccessIds::SetUids::setuids( $uid, $gid );

                    # send individual signals to avoid some race conditions
                    kill( $signal, @non_zombie_pids );
                    if ( kill( $signal, -1 ) == -1 ) {
                        syswrite( STDERR, "The system failed to send the “$signal” signal to all of procesess owned by ”$user” because of an error: $!\n" );
                    }
                    exit(0);
                }
            );

            #So that $? from this doesn’t pollute the global space,
            #which can make for nasty breakages like CPANEL-18244.
            local $?;

            Cpanel::Waitpid::sigsafe_blocking_waitpid($pid);
        }

        foreach my $proc ( @{$procs} ) {

            #So that $? from this doesn’t pollute the global space,
            #which can make for nasty breakages like CPANEL-18244.
            local $?;

            waitpid( $proc->{'pid'}, $Cpanel::Wait::Constants::WNOHANG );    #  in case its a child of us and in zombie state
        }

        return 1 if !@non_zombie_pids;

        $procs = _procs_for_uid($uid);
        return 1 if !scalar @$procs;

        Cpanel::TimeHiRes::sleep(0.1) if !$is_kill_signal;
    }
    return 0;
}

=head2 kill_users_processes( USER )

Terminate all processes owned by a user with TERM and then KILL

=head3 Arguments

Required:

  USER            - scalar:   The username to kill the processes for

=head3 Return Value

  1 - Success

=cut

# This is a "nice" way of killing the users processes
# we at least give them 300ms to shutdown
sub kill_users_processes {
    my ($user) = @_;
    if ( !kill_pids_owned_by( $user, 'TERM' ) ) {

        # Give the proceses some time to die
        Cpanel::TimeHiRes::sleep(0.3);
    }

    # We always need to do a forced kill
    # because TERM has a race window
    kill_pids_owned_by( $user, 'KILL' );
    return 1;
}

sub _procs_for_uid {
    my $uid = shift;

    return [] unless defined $uid;

    # Same logic form Cpanel::Services
    my $process_table = Cpanel::PsParser::fast_parse_ps( 'resolve_uids' => 0, 'want_uid' => $uid, 'exclude_kernel' => 1, 'exclude_self' => 1, 'skip_cmdline' => 1 );
    return [] unless $process_table && ref $process_table eq 'ARRAY';
    return $process_table;
}

1;

__END__
