package Cpanel::SSL::DCV::AnyAncestor;

# cpanel - Cpanel/SSL/DCV/AnyAncestor.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::SSL::DCV::AnyAncestor

=head1 SYNOPSIS

    my $dcv_tracker = Cpanel::SSL::DCV::AnyAncestor->new();

    $dcv_tracker->add_validated_domain('good.tld');

    $dcv_tracker->get_authz_domain('foo.good.tld');     #returns truthy

    $dcv_tracker->add_failed_domain('bad.tld');

    $dcv_tracker->get_authz_domain('unknown.tld');      #returns falsy

=head1 DESCRIPTION

Comodo’s DCV will look for and accept the relevant token on all parent
domains of each domain on a given CSR. That means that if a given CSR
has C<foo.bar.baz.org>, then any of the following can yield a successful DCV
for that domain:

=over

=item C<baz.org>

=item C<bar.baz.org>

=item C<foo.bar.baz.org> (the domain itself)

=back

(cf. L<https://secure.comodo.net/api/pdf/latest/Domain%20Control%20Validation.pdf>)

This class is a simple state tracker for this logic.

=head1 METHODS

=head2 I<CLASS>->new()

Returns a new instance.

=cut

sub new {
    return bless {}, shift;
}

=head2 I<OBJ>->add_validated_domain( $NAME )

Adds a new domain named $NAME to the list of successful domains.
All subdomains of this domain will be considered validated.

Addition of a subdomain when a parent domain already passsed validation
will trigger an exception. For contexts where this module is meaningful
there is never a reason to DCV a domain when a parent domain of that domain
has already passed.

Returns OBJ.

=cut

sub add_validated_domain {
    my ( $self, $name ) = @_;

    $self->_die_if_validated_or_failed($name);

    $self->{'_success'}{$name} = undef;

    return $self;
}

=head2 I<OBJ>->get_authz_domain( $NAME )

Returns the name of the validated domain if $NAME is validated, or
undef if $NAME isn’t validated.

This doesn’t distinguish between “not validated B<yet>” and “failed
validation” states.

=cut

sub get_authz_domain {
    my ( $self, $name ) = @_;

    my @labels = split m<\.>, $name;

    while (@labels) {
        my $this_name = join q<.>, @labels;
        return $this_name if exists $self->{'_success'}{$this_name};
        shift @labels;
    }

    return undef;
}

sub _die_if_validated_or_failed {
    my ( $self, $name ) = @_;

    if ( my $validated_as = $self->get_authz_domain($name) ) {
        die "“$name” already passed DCV (via $validated_as).";
    }

    if ( exists $self->{'_failure'}{$name} ) {
        die "“$name” already failed DCV.";
    }

    return;
}

#----------------------------------------------------------------------

=head2 I<OBJ>->add_failed_domain( $NAME, $REASON )

Adds a new domain named $NAME to the list of failed domains.

If $NAME is already considered a failure, then an exception is thrown.

$REASON can be a reference or a plain scalar.

Returns OBJ.

=cut

sub add_failed_domain {
    my ( $self, $name, $reason ) = @_;

    $self->_die_if_validated_or_failed($name);

    $self->{'_failure'}{$name} = $reason;

    return $self;
}

=head2 I<OBJ>->get_failures( $NAME )

Returns a hashref of domains and $REASON for the given $NAME.
The hashref can be empty. For example, if you give C<foo.example.com>,
you might get:

    {
        'example.com'     => '“example.com” failed because …',
        'foo.example.com' => '“foo.example.com” failed because …',
    }

=cut

sub get_failures {
    my ( $self, $name ) = @_;

    my %response;

    my @labels = split m<\.>, $name;

    while (@labels) {
        my $this_name = join q<.>, @labels;
        shift @labels;

        next if !exists $self->{'_failure'}{$this_name};

        $response{$this_name} = $self->{'_failure'}{$this_name};
    }

    return \%response;
}

1;
