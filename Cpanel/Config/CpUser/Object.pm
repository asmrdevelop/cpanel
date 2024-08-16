package Cpanel::Config::CpUser::Object;

# cpanel - Cpanel/Config/CpUser/Object.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Config::CpUser::Object

=head1 SYNOPSIS

    my $created_domains_ar = $cpuser_obj->domains_ar();

=head1 DESCRIPTION

This class provides simple accessors for the contents of a cpuser file.

=head1 OBJECT INTERNALS

The object’s internals are the hashref that L<Cpanel::Config::LoadCpUserFile>

=head1 SERIALIZATION

Instances of this class implement C<TO_JSON()>. (cf. L<JSON>)

=head1 SEE ALSO

L<Cpanel::Config::CpUser::Object::Update> implements logic for updating
instances of this class.

=cut

#----------------------------------------------------------------------

use parent 'Cpanel::Hash::JSONable';

use Class::XSAccessor (
    getters => {
        username => 'USER',
    },
);

#----------------------------------------------------------------------

=head1 METHODS

=head2 $obj = I<CLASS>->adopt( \%CPUSER )

Converts the passed-in hashref to a I<CLASS> instance.

=cut

sub adopt ( $class, $ref ) {
    return bless $ref, $class;
}

#----------------------------------------------------------------------

=head2 $domains_ar = I<OBJ>->domains_ar()

Returns a reference to an array of all of the user’s current domains
as stored in I<OBJ>. (This doesn’t include automatically-created
domains like C<www.> subdomains.)

=cut

sub domains_ar ($self) {
    return [ $self->{'DOMAIN'}, @{ $self->{'DOMAINS'} } ];
}

#----------------------------------------------------------------------

=head2 $domains_ar = I<OBJ>->contact_emails_ar()

Returns a reference to an array of the user’s contact email addresses
as stored in I<OBJ>.

=cut

sub contact_emails_ar ($self) {
    return [ grep { length } @{$self}{ 'CONTACTEMAIL', 'CONTACTEMAIL2' } ];
}

# ----------------------------------------------------------------------

=head2 @names = I<OBJ>->child_workloads( $WORKLOAD_NAME )

Returns the names of the account’s designated child workloads or,
in scalar context, the number of such workloads. Thus, a convenient way
to determine whether the account is a child account is to evaluate this
method’s return in boolean context.

An account with no child workloads is—counterintuitively, perhaps—a
“normal” account, capable of doing anything the system account can do.

=cut

sub child_workloads ($self) {

    # Only return the workload names if that’s specifically
    # what the caller wants.
    if (wantarray) {
        return if !$self->{'CHILD_WORKLOADS'};
        return split( m<,>, $self->{'CHILD_WORKLOADS'}, -1 );
    }

    return 0 if !$self->{'CHILD_WORKLOADS'};

    # In cases where the caller only cares about whether the
    # account is a child account, we can optimize by using tr
    # instead of split().
    return 1 + ( $self->{'CHILD_WORKLOADS'} =~ tr<,><> );
}

1;
