package Cpanel::iContact::TestMessage;

# cpanel - Cpanel/iContact/TestMessage.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::Locale ();

sub new {
    my ( $class, $body ) = @_;
    my $self = bless {}, $class;

    $self->{'_message_id'} = _generate_message_id();
    $self->{'_body'}       = $body;

    return $self;
}

sub get_subject {
    my ($self) = @_;
    return _locale()->maketext( 'Test message (ID: [_1])', $self->get_message_id() );
}

sub get_body {
    my ($self) = @_;
    return $self->{'_body'};
}

sub get_message_id {
    my ($self) = @_;
    return $self->{'_message_id'};
}

sub get_body_with_timestamp {
    my ($self) = @_;
    return _add_timestamp( $self->get_body() );
}

sub _generate_message_id {
    my $message_id = rand;
    $message_id =~ s<\A0\.><>;
    $message_id = join( '-', map { sprintf "%x", $_ } time, $message_id );

    return $message_id;
}

sub _add_timestamp {
    my ($msg) = @_;
    return "$msg\n\n" . _locale()->maketext( "This message was sent on [datetime,_1,date_format_full] at [datetime,_1,time_format_full].", time );
}

my $_locale;

sub _locale {
    return $_locale ||= Cpanel::Locale->get_handle();
}

1;
