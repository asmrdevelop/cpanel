package Cpanel::DnsUtils::Install::Result;

# cpanel - Cpanel/DnsUtils/Install/Result.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::DnsUtils::Install::Result

=head1 SYNOPSIS

    my $obj = Cpanel::DnsUtils::Install::Result->new( $state_hr );

    if ($obj->was_total_success()) { .. }

    my @zones_to_sync = $obj->get_success_zones();

=head1 DESCRIPTION

The return from L<Cpanel::DnsUtils::Install> is rather unwieldy.
This module attempts to smooth over the rough edges.

B<IMPORTANT:> In new code, please do not access the object internals.
Access to object internals will happen in old code because those
calls predate this object. Ideally, eventually we’ll migrate everything
to use this object’s methods, and then we can reconfigure the object
internals freely.

=cut

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $obj = I<CLASS>->new( %OPTS )

Returns an instance of this class. %OPTS are:

=over

=item * C<errors> - Arrayref of strings. The caller should generally ignore
this field except for debugging purposes. (TODO: Isn’t that what error
strings are for, though??) There currently is no accessor for this
information.

=item * C<zones_modified> - Arrayref of strings. There currently is no
accessor for this information.

=item * C<domain_status> - Arrayref of hashes. Each hash is:

=over

=item * C<domain> - The individual domain name for which an operation happened.

=item * C<status> - Boolean to indicate success or failure of the operation.

=item * C<msg> - A parsable string. It begins with a left bracket (C<[>).
Then, in case of failure (and only then), the string will include
C<$Cpanel::DnsUtils::Install::Processor::FAILURE_STRING>. After that comes a
comma-separated list of messages meant for human consumption. Finally, it
concludes with a right bracket (C<]>).

=back

=back

=cut

sub new {
    my ( $class, %opts ) = @_;

    return bless \%opts, $class;
}

#----------------------------------------------------------------------

=head2 $yn = I<OBJ>->was_any_success()

Indicates whether anything about the request succeeded.

=cut

sub was_any_success {

    # Something succeeded …
    return !!grep { !!$_->{'status'} } @{ $_[0]->{'domain_status'} };
}

=head2 $yn = I<OBJ>->was_total_success()

Indicates whether everything about the request succeeded.

=cut

sub was_total_success {

    # Nothing failed …
    return !grep { !$_->{'status'} } @{ $_[0]->{'domain_status'} };
}

#----------------------------------------------------------------------

=head2 I<OBJ>->for_each_domain( $TODO_CR )

Runs $TODO_CR for each domain name in the result.
$TODO_CR receives the domain name, a boolean to indicate success,
and a human-readable message that gives more details.

=cut

sub for_each_domain {
    my ( $self, $todo_cr ) = @_;

    for my $d_hr ( @{ $self->{'domain_status'} } ) {
        $todo_cr->( @{$d_hr}{ 'domain', 'status', 'msg' } );
    }

    return;
}

=head2 I<OBJ>->TO_JSON()

Return a copy of internal hashref in the object for backwards compatibility.

This should ONLY be used by JSON::XS

=cut

sub TO_JSON {
    return { %{ $_[0] } };
}

1;
