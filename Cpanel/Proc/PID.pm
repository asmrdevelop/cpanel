package Cpanel::Proc::PID;

# cpanel - Cpanel/Proc/PID.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Exception ();
use Cpanel::LoadFile  ();

# for testing
our $PROC_PATH = '/proc';

sub new {
    my ( $class, $pid ) = @_;

    if ( !$pid || $pid =~ tr{0-9}{}c ) {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a valid process ID.', [$pid] );
    }

    my $self = bless { _pid => $pid }, $class;

    $self->ctime();

    return $self;
}

sub _proc_pid_path {
    my ($self) = @_;

    return "$PROC_PATH/$self->{'_pid'}";
}

sub elapsed_time {
    my ($self) = @_;
    my $start_time = ( stat( $self->_proc_pid_path() ) )[8] || $self->ctime();

    return ( time() - $start_time );
}

sub pid {
    my ($self) = @_;
    return $self->{'_pid'};
}

sub uid {
    my ($self) = @_;

    if ( !defined $self->{'_uid'} ) {
        $self->{'_uid'} = ( stat $self->_proc_pid_path() )[4] // $self->_ended_die();
    }

    return $self->{'_uid'};
}

sub ctime {
    my ($self) = @_;

    return $self->{'_ctime'} ||= do {
        $self->_fetch_ctime() or $self->_ended_die();
    };
}

sub _fetch_ctime {
    my ($self) = @_;

    my $ctime = ( stat $self->_proc_pid_path() )[10];

    return $ctime;
}

sub _ended_die {
    my ($self) = @_;

    die Cpanel::Exception::create( 'ProcessNotRunning', [ pid => $self->{'_pid'} ] );
}

sub is_running {
    my ($self) = @_;

    my $new_ctime = $self->_fetch_ctime();
    return ( $new_ctime && ( $self->{'_ctime'} == $new_ctime ) ) ? 1 : 0;
}

sub state {
    my ($self) = @_;

    my $stat = Cpanel::LoadFile::load_if_exists( $self->_proc_pid_path() . '/stat' );
    $self->_ended_die() if !defined $stat;

    # Per proc(5), this is always a single letter.
    return substr( $stat, 2 + rindex( $stat, ')' ), 1 );
}

sub cmdline {
    my ($self) = @_;

    # Clone was causing cphulkd to randomly crash. Since we only need to
    # copy an array we just use a shallow copy
    return [
        @{
            $self->{'_cmdline'} ||= do {
                my $cmdline_r = Cpanel::LoadFile::load_r_if_exists( $self->_proc_pid_path() . '/cmdline' );
                $self->_ended_die() if !defined $cmdline_r;
                [ split m{\0}, $$cmdline_r ];
            };
        }
    ];
}

1;
