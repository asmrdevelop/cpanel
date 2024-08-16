package Cpanel::Logd::StatsLog;

# cpanel - Cpanel/Logd/StatsLog.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=pod

=encoding utf-8

=head1 NAME

Cpanel::Logd::StatsLog - Logging functionality for cpanellogd

=head2 SYNOPSIS

    my $logger = Cpanel::Logd::StatsLog->new();

    #optional
    $logger->redirect_fh_to_me(\*STDERR) or die $!;

    $logger->log(3, 'This is my log message.');

=head1 DESCRIPTION

This object implements cpanellogd’s logging functionality.

NOTE: This module is kept small for now, which means avoiding
C<Cpanel::Exception>.

=head1 METHODS

=cut

use strict;

# Do not use in anything here as this is resident in memory all the time

my $LOG_PERMS = 0600;

my $STLOG_FH;

#Override for tests.
sub _get_cpconf {
    if ( $INC{'Cpanel/Config/LoadCpConf.pm'} ) {
        return Cpanel::Config::LoadCpConf::loadcpconf();
    }
    else {
        require Cpanel::Config::LoadCpConf::Micro;
        return Cpanel::Config::LoadCpConf::Micro::loadcpconf();
    }
}

=pod

B<new( [ FH ] ) > (constructor)

The file handle, if given is used as a destination for the logs.
This file handle will NOT be C<close()>d when this object goes away.

This function overwrites global $! and $^E.

=cut

sub new {
    my ( $class, $fh, $cpconf ) = @_;

    my $self = {
        _orig_pid => $$,
        _fh       => $fh,
    };
    bless $self, $class;

    if ( !$fh ) {
        $self->{'_close_on_DESTROY'} = 1;

        $cpconf ||= _get_cpconf();

        #NOTE: Even if we are going to clobber what’s there, we still
        #open the stats log in append mode. This way if something else
        #were to write to the same log file, we won’t clobber what
        #else was there.
        open( $fh, '>>', $cpconf->{'stats_log'} ) or do {
            die "Failed to open(>> $cpconf->{'stats_log'}): $!";
        };

        # Limit use of Cpanel::Sys::Chattr to a transient subprocess
        my $append_pid = fork();
        if ( !defined $append_pid ) {
            die "Failed to fork";
        }
        elsif ( $append_pid == 0 ) {
            require Cpanel::Sys::Chattr;

            my $need_chmod = ( ( stat($fh) )[2] & 0777 ) != $LOG_PERMS;

            if ( $need_chmod || !$cpconf->{'keepstatslog'} ) {
                Cpanel::Sys::Chattr::remove_attribute( $fh, 'APPEND' );
                chmod $LOG_PERMS, $fh if $need_chmod;
                truncate( $fh, 0 ) if !$cpconf->{'keepstatslog'};
            }

            Cpanel::Sys::Chattr::set_attribute( $fh, 'APPEND' );
            exit;
        }

        waitpid( $append_pid, 0 );

        $self->{'_fh'} = $fh;

        #autoflush...
        my $old_fh = select $fh;    ##no critic qw(ProhibitOneArgSelect)
        $| = 1;
        select $old_fh;             ##no critic qw(ProhibitOneArgSelect)

        my $time = time();

        $self->_printf(
            "-- RESTART MARKER (PID %d at %s, %s)--\n",
            $$,
            _get_timestamp($time),
            $time,
        );

    }

    return $self;
}

sub DESTROY {
    my ($self) = @_;

    return if $self->{'_orig_pid'} != $$;

    if ( $self->{'_close_on_DESTROY'} ) {
        close $self->{'_fh'} or warn "Failed to close() stats log: $!";
    }

    return;
}

=pod

B<redirect_fh_to_me( FH ) >

Useful for redirecting multiple output streams to the same log file.

This overwrites global $! and $^E.

=cut

sub redirect_fh_to_me {
    my ( $self, $fh ) = @_;

    return open( $fh, '>&', $self->{'_fh'} );
}

=pod

B<log( LEVEL, MESSAGE ) >

The “workhorse” method of this class!

If LEVEL is beneath the cpanel.config’s “statsloglevel”, then this
does nothing; otherwise, it prints the entry to the log file,
prefixes with a timestamp and followed by a newline.

This overwrites global $! and $^E.

=cut

sub log {
    my ( $self, $level, $message ) = @_;

    return undef if _get_cpconf()->{'statsloglevel'} < $level;

    return $self->_printf(
        "[%s] %s\n",
        _get_timestamp(),
        $message,
    );
}

sub _get_timestamp {
    my ($unixtime) = @_;

    require Cpanel::Time::Local;

    return Cpanel::Time::Local::localtime2timestamp($unixtime);
}

sub _printf {    ## no critic qw(RequireArgUnpacking)
    my ($self) = shift;

    my $out = printf { $self->{'_fh'} } @_ or do {
        warn "Failed to write to stats log: $!";
        return undef;
    };

    return $out;
}

1;
