
# cpanel - Cpanel/Transport/Response.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Transport::Response;

use strict;

# Ensure that this is treated as a string when a string is expected
# use overload '""' => \&message;

{

    package Cpanel::Transport::Exception;
    our @ISA = ('Cpanel::Transport::Response');

    # call_stack is currently not used anywhere, but it provides good data that can be tapped in to by anyone trying to debug a problem
    sub _post_constructor {
        my $self = shift;
        my @call_stack;
        my $i = 2;
        while ( my @caller = caller( $i++ ) ) {
            last if ( $caller[3] =~ /::BEGIN$/ );

            unshift @call_stack,
              {
                'subroutine' => $caller[3],
                'line'       => $caller[2],
                'file'       => $caller[1],
              };
        }

        $self->default_msg if $self->can('default_msg');

        $self->{'call_stack'} = \@call_stack;
        return $self->{'call_stack'};
    }

    sub set_success {
        my ($ref) = @_;
        $ref->{'success'} = 0;
        return;
    }
    1;
}

{

    package Cpanel::Transport::Exception::Network;
    our @ISA = ('Cpanel::Transport::Exception');
    1;
}

{

    package Cpanel::Transport::Exception::PathNotFound;
    our @ISA = ('Cpanel::Transport::Exception');
    1;
}

{

    package Cpanel::Transport::Exception::Network::Authentication;
    our @ISA = ('Cpanel::Transport::Exception::Network');
    1;
}

{

    package Cpanel::Transport::Exception::Network::Connection;
    our @ISA = ('Cpanel::Transport::Exception::Network');
    1;
}

{

    package Cpanel::Transport::Exception::NotImplemented;
    our @ISA = ('Cpanel::Transport::Exception');

    sub default_msg {
        my ($ref) = @_;
        $ref->{'msg'} = "Method Not Implemented";
        return;
    }
    1;
}

{

    package Cpanel::Transport::Exception::MissingParameter;
    our @ISA = ('Cpanel::Transport::Exception');
    1;
}

{

    package Cpanel::Transport::Exception::InvalidParameter;
    our @ISA = ('Cpanel::Transport::Exception');
    1;
}

# To create a new response obj:
# Cpanel::Transport::Response->new( \@parameters, $status [, $msg, $data ] );

sub new {
    my ( $class, $params, $status, $msg, $data ) = @_;

    my @caller = caller(1);
    my $self   = bless {
        'parent' => $caller[3],
        'params' => $params,
        'data'   => {},
    }, $class;

    $self->set_success($status);

    if ( defined $msg ) {
        $self->set_msg($msg);
    }
    elsif ( $self->{'success'} ) {
        $self->set_msg('Ok');
    }
    else {
        $self->set_msg('Unknown Error');
    }

    $self->set_data($data)                                    if defined $data;
    $self->_post_constructor( $params, $status, $msg, $data ) if $self->can('_post_constructor');
    return $self;
}

# caller - describes the function called to create the Cpanel::Transport::Response object
# (e.g. Cpanel::Transport::Files::SFTP::put)
sub parent {
    my ($ref) = @_;
    return $ref->{'parent'};
}

sub params {
    my ($ref) = @_;
    return $ref->{'params'};
}

# success - boolean describing whether the action was successful, or not.
sub success {
    my ($ref) = @_;
    return $ref->{'success'};
}

sub data {
    my ($ref) = @_;
    return $ref->{'data'};
}

sub message {
    my ($ref) = @_;
    return $ref->{'msg'};
}

sub set_success {
    my ( $self, $status ) = @_;
    $self->{'success'} = $status ? 1 : 0;
    return;
}

sub set_msg {
    my ( $self, $msg ) = @_;
    if ( $self->{'success'} ) {
        $self->{'msg'} = defined $msg ? $msg : 'Ok';
    }
    else {
        if ( defined $msg ) {
            $self->{'msg'} = $msg;
        }
        else {
            warn "Cpanel::Transport::Response::set_success was called with a fail status & no message.";
        }
    }
    return;
}

sub set_data {
    my ( $self, $data ) = @_;
    $self->{'data'} = defined $data ? $data : {};
    return;
}

{

    package Cpanel::Transport::Response::ls;

    our @ISA = ('Cpanel::Transport::Response');

    sub find_file {
        my ( $self, $filename ) = @_;

        if ( !$self->success ) {
            return 0;
        }
        foreach my $path_hr ( @{ $self->{'data'} } ) {
            return 1 if $path_hr->{'filename'} eq $filename;
        }
        return 0;
    }

    1;

}

1;
