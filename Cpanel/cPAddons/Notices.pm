
# cpanel - Cpanel/cPAddons/Notices.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::cPAddons::Notices;

use strict;
use warnings;

our $notices;
our $id = 0;

=head1 NAME

Cpanel::cPAddons::Notices

=head1 DESCRIPTION

Class to aggregate diagnostic messages into a data structure which can be queried later.

=head1 NOTICE TYPES

 'critical_error',
 'error',
 'warning',
 'info',
 'success',
 'plain',
 'pre',
 'html'

=head1 FUNCTIONS

=head2 singleton()

Returns an instance of Cpanel::cPAddons::Notices. The same instance will be reused across
multiple calls.

=cut

sub singleton {
    $notices = Cpanel::cPAddons::Notices->new() if !$notices;
    return $notices;
}

=head2 new()

Regular constructor. Returns an instance of Cpanel::cPAddons::Notices.

=cut

sub new {
    my ($class) = @_;

    my $self = bless {
        notices => [],
        summary => {},
    }, $class;

    return $self;
}

=head2 has(TYPE, ...)

Check whether the specified notice type or types exist in the object.

=head3 Arguments

- TYPE - String - The notice type. See the NOTICE TYPES section above for
a list of possible values.

- ... - You may specify multiple types, and they will be ORed.

=head3 Returns

True if any of the specified message types exist in the object;
false otherwise.

=cut

sub has {
    my ( $self, @types ) = @_;

    return @{ $self->{notices} } ? 1 : 0 if !@types;

    foreach my $type (@types) {
        return 1 if ( $self->{summary}{$type} );
    }
    return 0;
}

=head2 get_list()

Get the list of notices.

=head3 Argument

none

=head3 Returns

An array ref of notice data structures, each of which contains:

- message - String - The notice text

- type - String - The notice type (see NOTICE TYPES above)

- id - String - The id to use for the notice in HTML elements. This is provided for the
caller's convenience and is not directly used by the Notices object.

=cut

sub get_list {
    my ($self) = @_;
    return $self->{notices};
}

sub get_error_messages {
    my ($self) = @_;
    my @messages;
    for my $notice ( @{ $self->{notices} || [] } ) {
        if ( $notice->{type} eq 'critical_error' or $notice->{type} eq 'error' ) {
            push @messages, $notice->{message};
        }
    }
    return \@messages;
}

=head2 clear()

Clears all notices from the object.

=cut

sub clear {
    my ($self) = @_;
    $self->{notices} = [];
    $self->{summary} = {};
    return;
}

=head2 add_critical_error(MESSAGE, [id => ...], [list_items => ...])

Add a critical error to the object.

You may optionally specify an id if you don't want one to be automatically generated.

=cut

sub add_critical_error {
    my ( $self, $message, %opts ) = @_;
    return _carp("No message passed") if !$message;
    $self->{summary}{critical_error} = 1;
    push @{ $self->{notices} }, {
        message => $message,
        type    => 'critical_error',
        id      => $opts{id} || 'critical_error_' . $id++,
        ( defined $opts{list_items} ? ( list_items => $opts{list_items} ) : () ),
    };
    return;
}

=head2 add_error(MESSAGE, [id => ...], [list_items => ...])

Add an error to the object.

You may optionally specify an id if you don't want one to be automatically generated.

=cut

sub add_error {
    my ( $self, $message, %opts ) = @_;
    return _carp("No message passed") if !$message;
    $self->{summary}{error} = 1;
    push @{ $self->{notices} }, {
        message => $message,
        type    => 'error',
        id      => $opts{id} || 'error_' . $id++,
        ( defined $opts{list_items} ? ( list_items => $opts{list_items} ) : () ),
    };
    return;
}

=head2 add_warning(MESSAGE, [id => ...], [list_items => ...])

Add a warning to the object.

You may optionally specify an id if you don't want one to be automatically generated.

=cut

sub add_warning {
    my ( $self, $message, %opts ) = @_;
    return _carp("No message passed") if !$message;
    $self->{summary}{warning} = 1;
    push @{ $self->{notices} }, {
        message => $message,
        type    => 'warning',
        id      => $opts{id} || 'warning_' . $id++,
        ( defined $opts{list_items} ? ( list_items => $opts{list_items} ) : () ),
    };
    return;
}

=head2 add_info(MESSAGE, [id => ...], [list_items => ...])

Add an info notice to the object.

You may optionally specify an id if you don't want one to be automatically generated.

=cut

sub add_info {
    my ( $self, $message, %opts ) = @_;
    return _carp("No message passed") if !$message;
    $self->{summary}{info} = 1;
    push @{ $self->{notices} }, {
        message => $message,
        type    => 'info',
        id      => $opts{id} || 'info_' . $id++,
        ( defined $opts{list_items} ? ( list_items => $opts{list_items} ) : () ),
    };
    return;
}

=head2 add_success(MESSAGE, [id => ...], [list_items => ...])

Add a success message to the object.

You may optionally specify an id if you don't want one to be automatically generated.

=cut

sub add_success {
    my ( $self, $message, %opts ) = @_;
    return _carp("No message passed") if !$message;
    $self->{summary}{success} = 1;
    push @{ $self->{notices} }, {
        message => $message,
        type    => 'success',
        id      => $opts{id} || 'success_' . $id++,
        ( defined $opts{list_items} ? ( list_items => $opts{list_items} ) : () ),
    };
    return;
}

=head2 add_plain(MESSAGE, [id => ...], [list_items => ...])

Add a notice of type 'plain' to the object.

You may optionally specify an id if you don't want one to be automatically generated.

=cut

sub add_plain {
    my ( $self, $message, %opts ) = @_;
    return _carp("No message passed") if !$message;
    $self->{summary}{plain} = 1;
    push @{ $self->{notices} }, {
        message => $message,
        type    => 'plain',
        id      => $opts{id} || 'plain_' . $id++,
        ( defined $opts{list_items} ? ( list_items => $opts{list_items} ) : () ),
    };
    return;
}

=head2 add_pre(MESSAGE, [id => ...], [list_items => ...])

Add a notice of type 'pre' to the object.

You may optionally specify an id if you don't want one to be automatically generated.

=cut

sub add_pre {
    my ( $self, $message, %opts ) = @_;
    return _carp("No message passed") if !$message;
    $self->{summary}{pre} = 1;
    push @{ $self->{notices} }, {
        message => $message,
        type    => 'pre',
        id      => $opts{id} || 'pre_' . $id++,
        ( defined $opts{list_items} ? ( list_items => $opts{list_items} ) : () ),
    };
    return;
}

=head2 add_html(MESSAGE, [id => ...], [list_items => ...])

Add a notice of type 'html' to the object.

You may optionally specify an id if you don't want one to be automatically generated.

=cut

sub add_html {
    my ( $self, $message, %opts ) = @_;
    return _carp("No message passed") if !$message;
    $self->{summary}{html} = 1;
    push @{ $self->{notices} }, {
        message => $message,
        type    => 'html',
        id      => $opts{id} || 'html_' . $id++,
    };
    return;
}

sub _carp {

    # Defer loading carp since we do not want to perlcc it in since we only call it on error
    require Carp;    # no loadmodule here
    return Carp::carp(@_);
}

1;
