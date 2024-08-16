package Cpanel::Backup::Transport::Session;

# cpanel - Cpanel/Backup/Transport/Session.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::Locale            ();
use Cpanel::Backup::Transport ();

our @ISA = ('Cpanel::Backup::Transport');
my $locale;

sub new {
    my ( $class, $session_id ) = @_;
    $locale ||= Cpanel::Locale->get_handle();

    my $self = $class->SUPER::new();
    $self->{'session_id'} = $session_id;
    bless $self, $class;
    return $self;
}

sub get_transports {
    my ($self)     = @_;
    my $session_id = $self->{'session_id'};
    my %transports = %{ $self->get_enabled_destinations() };
    foreach my $transport ( keys %transports ) {
        if ( exists $self->{'destinations'}->{$transport}->{'disabled'}
            && $self->{'destinations'}->{$transport}->{'disabled'} ) {
            delete $transports{$transport};
        }
        if ( exists $self->{'destinations'}->{$transport}->{'sessions'}->{$session_id}->{'disabled'} ) {
            delete $transports{$transport};
        }
    }
    return \%transports;
}

#
# Perform a check on all the destinations and, if any are offline,
# disable them for the current session.
# Optionally, log that the destination transport has been disabled.
#
sub check_all_destinations {
    my ( $self, $logger ) = @_;

    # Temp disable stdout/stderr so the transport code libraries
    # don't dump a bunch of extraneous stuff to the screen
    local *STDOUT;
    local *STDERR;
    open STDOUT, '>', '/dev/null' || print STDERR "Could not redirect STDOUT: $!\n";
    open STDERR, '>', '/dev/null' || print STDERR "Could not redirect STDERR: $!\n";

    my $transports = $self->get_transports();

    # Test out each transport and disable it if it is ofline
    foreach my $transport_id ( keys %$transports ) {

        my ( $success, $reason ) = $self->check_destination($transport_id);

        unless ($success) {

            if ($logger) {
                $logger->warn("Disabling backup destination $transports->{name} for session $self->{session_id}:  $reason");
            }

            $self->disable( $transport_id, $reason );
        }
    }
    return;
}

sub disable {
    my ( $self, $transport_id, $reason ) = @_;
    my $session_id = $self->{'session_id'};

    # Don't disable if already disabled
    return if $self->is_disabled($transport_id);

    if ( !exists $self->{'destinations'}->{$transport_id}->{'sessions'}->{$session_id} ) {
        $self->{'destinations'}->{$transport_id}->{'sessions'}->{$session_id} = {};
    }

    $self->{'destinations'}->{$transport_id}->{'disabled'}       = 1;
    $self->{'destinations'}->{$transport_id}->{'disable_reason'} = Cpanel::Backup::Transport::parse_exception($reason);
    $self->_save_transport($transport_id);

    # Send message to the admin that we have disabled this
    Cpanel::Backup::Transport::send_disabled_message(
        'name'        => $self->{'destinations'}->{$transport_id}->{'name'},
        'type'        => $self->{'destinations'}->{$transport_id}->{'type'},
        'remote_host' => $self->{'destinations'}->{$transport_id}->{'host'},
        'reason'      => $reason
    );
    return;
}

sub is_disabled {
    my ( $self, $transport_id ) = @_;
    my $session_id = $self->{'session_id'};

    if ( $self->SUPER::is_disabled($transport_id) ) {
        return 1;
    }

    if ( !exists $self->{'destinations'}->{$transport_id}->{'sessions'}->{$session_id} ) {
        return 0;
    }

    my $session_hr = $self->{'destinations'}->{$transport_id}->{'sessions'}->{$session_id};
    return $session_hr->{'disabled'};
}

#
# Wipe the session info from the config files of all the transports
# This can be usefull to clean it out after a lot of testing
#
sub clear_all_session_info {
    my ($self) = @_;

    foreach my $id ( keys %{ $self->{'destinations'} } ) {
        $self->clear_session_info($id);
    }
    return;
}

#
# Wipe the session info from the config file
# This can be usefull to clean it out after a lot of testing
#
sub clear_session_info {
    my ( $self, $transport_id ) = @_;

    unless ( exists $self->{'destinations'}->{$transport_id}->{'sessions'} ) {
        return;
    }

    delete $self->{'destinations'}->{$transport_id}->{'sessions'};
    $self->_save_transport($transport_id);
    return;
}

# Always returns undef, as we no longer auto-disable a destinations anymore
sub handle_error {
    my ( $self, $transport, $error_class, $error_msg ) = @_;

    my $ERROR_THRESHOLD = Cpanel::Backup::Transport::get_error_threshold();

    my $session_id = $self->{'session_id'};
    if ( !exists $self->{'destinations'}->{$transport}->{'sessions'}->{$session_id} ) {
        $self->{'destinations'}->{$transport}->{'sessions'}->{$session_id} = {};
    }

    my $session_hr = $self->{'destinations'}->{$transport}->{'sessions'}->{$session_id};
    if ( !exists $session_hr->{'errors'} ) {
        $session_hr->{'errors'} = [];
    }
    push @{ $session_hr->{'errors'} }, { $error_class => $error_msg };

    return;
}

# Get an error object, return 1 if the transport is disabled as a result of this action
# return 0 if it's enabled.
sub parse_error {
    my ( $self, $transport_id, $error_obj ) = @_;
    my ( $error_class, $error_msg ) = ( 'Unknown', $error_obj );
    print STDERR "Error encountered\n";
    if ( ref $error_obj ) {
        print STDERR "Error is an object reference of type ref $error_obj\n";
        $error_class = ref $error_obj;
        $error_msg   = $error_obj->message();
    }
    else {
        print STDERR "Error is not a reference $error_obj\n";
    }
    return $self->handle_error( $transport_id, $error_class, $error_msg );
}

1;
