package Cpanel::Server::SSE::cpanel::UserTasks::Event;

# cpanel - Cpanel/Server/SSE/cpanel/UserTasks/Event.pm
#                                                  Copyright 2023 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::Exception ();
use Cpanel::TimeHiRes ();

use Simple::Accessor qw{
  data
  event
  id

  task_id
};

# type is mandatory
# task_id is optional

use parent qw{
  Cpanel::Interface::JSON
};

=encoding utf8

=head1 NAME

Cpanel::Server::SSE::cpanel::UserTasks::Event - base class for events

=head1 SYNOPSIS

    package MyEvent;

    use parent 'Cpanel::Server::SSE::cpanel::UserTasks::Event';

    use constant EVENT_TYPE => q[my_event_type];;

=head2 adopt( $hash )

Adopt a hash and bless it to the current class

=cut

sub adopt ( $class, $ref ) {
    return $ref if $ref && UNIVERSAL::isa( $ref, $class );

    return bless $ref, $class;
}

sub build ( $self, %opts ) {

    $self->event;
    $self->data;
    $self->id;

    return $self;
}

sub _build_id ($self) {
    return Cpanel::TimeHiRes::time();
}

sub _build_data ($self) {    # can be a string or HashRef, ArrayRef...
    return '';
}

sub _build_event ($self) {
    return $self->{type} // $self->{event_type} // $self->EVENT_TYPE;
}

sub EVENT_TYPE {
    die Cpanel::Exception::create( 'MissingParameter', 'The required parameter “[_1]” is not set.', ['EVENT_TYPE'] );
}

=head2 $self->TO_JSON()

Convert the event to a 'json' version we can send to the listener.

=cut

sub TO_JSON ($self) {

    my $json = { id => $self->id, event => $self->event };
    $json->{task_id} = $self->task_id if defined $self->task_id;
    my $data = $self->data;

    $json->{data} = $self->to_json( length $data ? $data : $json );

    return $json;
}

1;
