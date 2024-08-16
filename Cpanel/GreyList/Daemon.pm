package Cpanel::GreyList::Daemon;

# cpanel - Cpanel/GreyList/Daemon.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use base 'Cpanel::UnixDaemon';

use IO::Select       ();
use IO::Socket::UNIX ();

use Cpanel::GreyList::Config ();

use Cpanel::MemUsage::Daemons::Banned ();

Cpanel::MemUsage::Daemons::Banned::check();

my $MAX_FILEHANDLES_EXPECTED_TO_BE_OPEN = 1000;

sub NAME        { return 'cpgreylistd' }
sub PRETTY_NAME { return 'cPGreyListd' }
sub PID_FILE    { return Cpanel::GreyList::Config::get_pid_file() }
sub LOGFILE     { return Cpanel::GreyList::Config::get_logfile_path() }

my $PURGE_INTERVAL   = Cpanel::GreyList::Config::get_purge_interval_mins() * 60;
my $TIMEOUT_FOR_CHLD = Cpanel::GreyList::Config::get_child_timeout_secs();
my $MAX_NUM_OF_CHLD  = Cpanel::GreyList::Config::get_max_child_procs();

sub SOCKET_PATH { return Cpanel::GreyList::Config::get_socket_path() }

sub _set_socket_permissions {
    my ($self) = @_;

    # exim needs to be able to use this socket
    my $mail_gid = ( getpwnam('mail') )[3];
    chown 0, $mail_gid, $self->SOCKET_PATH();
    chmod 0660, $self->SOCKET_PATH();

    return;
}

sub RESTART_FUNC {
    return sub {
        my ( $listener_fileno, $extra_args_ref ) = @_;
        $extra_args_ref //= [];
        $SIG{'ALRM'} = $SIG{'USR1'} = $SIG{'HUP'} = 'IGNORE';    ## no critic qw(Variables::RequireLocalizedPunctuationVars)
        my @exec_args = ( '--start', '--listen=' . $listener_fileno );
        push @exec_args, $extra_args_ref->@*;
        _exec( '/usr/local/cpanel/libexec/cpgreylistd', @exec_args );
    };
}

sub _exec {
    exec @_ or die "exec(@_): $!";
}

sub _read_request {
    my ( $self, $socket ) = @_;
    chomp( my $line = readline $socket );

    # _read_request expects an array not an arrayref
    # as it will pass the arrayref to _handle_request
    return split / /, $line, 5;
}

sub _handle_request {
    my ( $self, $op, $data_ar ) = @_;

    my $reply;

    require Cpanel::GreyList::Handler;
    my $op_handler = Cpanel::GreyList::Handler->new();
    if (   $op =~ m/^(should_defer|purge_old_records|get_deferred_list|create_trusted_host|read_trusted_hosts|delete_trusted_host)$/
        && $op_handler->can($op) ) {
        $reply = $op_handler->$op( $self->{'logger'}, $data_ar );
    }
    else {
        $self->{'logger'}->info("Unknown OP '$op'");
    }

    return $reply . "\n";
}

#####################################

sub _periodic_task {
    my $self = shift;

    alarm $PURGE_INTERVAL;
    my $socket = IO::Socket::UNIX->new(
        Type => Socket::SOCK_STREAM(),
        Peer => $self->SOCKET_PATH(),
    ) or $self->{'logger'}->warn("Failed to purge old records: $!\n");
    print $socket "purge_old_records\n";
    return 1;
}

#####################################

sub _cleanup {
    my ($self) = @_;
    unlink $self->SOCKET_PATH();
    return;
}

1;
