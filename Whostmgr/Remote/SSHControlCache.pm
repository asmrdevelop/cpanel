package Whostmgr::Remote::SSHControlCache;

# cpanel - Whostmgr/Remote/SSHControlCache.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Destruct ();

my %UNIQUES = ( 'authuser' => 1, 'sshkey' => 1, 'host' => 1, 'port' => 1 );

sub new {
    my ($class) = @_;

    my $self = { '__active_pid' => $$, 'connections' => {} };

    bless $self, $class;

    return $self;
}

sub _handle_pid_change {
    my ($self) = @_;

    my $current_pid = $$;

    if ( $self->{'__active_pid'} != $current_pid ) {

        # All the connections belong to another process
        # and will be handled there.
        $self->{'connections'} = {};

        # The active pid is the new pid
        $self->{'__active_pid'} = $current_pid;
    }

    return $self->{'__active_pid'};
}

sub _get_args_key {
    my ( $self, $cmd_ref_hr ) = @_;

    my %args;

    for my $key ( keys %$cmd_ref_hr ) {
        $key =~ tr/A-Z/a-z/;
        next if !$UNIQUES{$key};
        $args{$key} = $cmd_ref_hr->{$key};
    }

    return join( '___', map { $_ . '=' . $args{$_} } sort keys %args );
}

#This will ALTER the passed-in hashref!
sub augment_sshcontrol_command {
    my ( $self, $cmd_ref_hr ) = @_;

    my $args_key = $self->_get_args_key($cmd_ref_hr);

    my $active_pid = $self->_handle_pid_change();

    # If we re-augment we need to kill the existing master
    if ( $cmd_ref_hr->{'external_master'} ) {
        if ( $self->{'connections'}{$args_key} ) {
            require Cpanel::Kill::Single;
            Cpanel::Kill::Single::safekill_single_pid( $self->{'connections'}{$args_key}{'pid'}, 1 );
            delete $self->{'connections'}{$args_key};
        }
        delete $cmd_ref_hr->{'external_master'};
        $cmd_ref_hr->{'stay_alive'} = 1;

    }

    # We have an existing master (not a reaugment)
    elsif ( $self->{'connections'}{$args_key} ) {
        $cmd_ref_hr->{'external_master'} = $self->{'connections'}{$args_key}{'ctl_path'};
    }

    # We do not have an existing master (not a reaugment)
    elsif ( !$cmd_ref_hr->{'stay_alive'} ) {
        $cmd_ref_hr->{'stay_alive'} = 1;
    }

    $cmd_ref_hr->{'die_on_pid'} ||= $active_pid;

    return $args_key;
}

sub register_sshcontrol_master {
    my ( $self, $args_key, $ctl_path, $pid ) = @_;

    my $ref = $self->{'connections'}{$args_key} ||= {};

    if ( $ref->{'pid'} ) {
        require Cpanel::Kill::Single;
        Cpanel::Kill::Single::safekill_single_pid( $self->{'connections'}{$args_key}{'pid'}, 1 );    #reconnect - kill old broken child
    }

    $ref->{'ctl_path'} = $ctl_path;
    $ref->{'pid'}      = $pid;

    return 1;
}

sub destroy_connection_by_args_key {
    my ( $self, $args_key ) = @_;

    my $connection = $self->{'connections'}{$args_key};

    return if !$connection;

    require Cpanel::Kill::Single;
    my $kill = Cpanel::Kill::Single::safekill_single_pid( $connection->{'pid'}, 1 );

    delete $self->{'connections'}{$args_key};

    return $kill;
}

sub DESTROY {
    my ($self) = @_;

    # Only kill connections that this process made
    return 0 if $self->{'__active_pid'} != $$;

    if ( scalar keys %{ $self->{'connections'} } ) {
        return if Cpanel::Destruct::in_dangerous_global_destruction();

        foreach my $args_key ( keys %{ $self->{'connections'} } ) {
            $self->destroy_connection_by_args_key($args_key);
        }
    }

    return 1;
}

1;
