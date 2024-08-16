package Cpanel::Expect;

# cpanel - Cpanel/Expect.pm                        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use base qw(Expect);

use POSIX ();    # Expect will use this anyways

# We need to send \r twice as some shells' PROMPT_COMMAND
# will cause our matching to fail otherwise.
my $COMMAND_TERMINATOR        = "\r\r";
my $SOCKET_COMMAND_TERMINATOR = "\n\n";

#Since we don’t "own" the Expect.pm logic (i.e., it comes from CPAN,
#not from us), it's safer to add our own logic using the "inside-out" pattern.
my %instance_data;

#Like send(), but appends a $COMMAND_TERMINATOR to the given input.
sub do {    ##no critic qw(RequireArgUnpacking)
            # $_[0]: self
            # $_[1]: cmd
    my $self = $_[0];

    return $self->send( $_[1] . $self->get_command_terminator() );
}

sub get_command_terminator {
    my ($self) = @_;
    return $self->is_tty() ? $COMMAND_TERMINATOR : $SOCKET_COMMAND_TERMINATOR;
}

sub shell_name {
    my ( $self, $new_shell_name ) = @_;

    if ( defined $new_shell_name ) {
        $instance_data{$self}{'shell_name'} = $new_shell_name;
    }

    return $instance_data{$self}{'shell_name'};
}

sub shell_is_setup {
    my ( $self, $new_shell_is_setup ) = @_;

    if ( defined $new_shell_is_setup ) {
        $instance_data{$self}{'shell_is_setup'} = $new_shell_is_setup;
    }

    return $instance_data{$self}{'shell_is_setup'};
}

sub is_tty {
    my ($self) = @_;

    if ( !defined ${*$self}{'is_tty'} ) {
        ${*$self}{'is_tty'} = POSIX::isatty($self);
    }
    return ${*$self}{'is_tty'};
}

sub DESTROY {
    my ($self) = @_;

    delete $instance_data{$self};

    return $self->SUPER::DESTROY();
}

1;
