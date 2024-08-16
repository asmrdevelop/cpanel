
# cpanel - Cpanel/UserManager/AnnotationList.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::UserManager::AnnotationList;

use strict;

=head1 NAME

Cpanel::UserManager::AnnotationList

=head1 CONSTRUCTION

The constructor accepts a single argument, which is an array ref of Cpanel::UserManager::Annotation objects.

=cut

sub new {
    my ( $package, $annotations_ar ) = @_;

    my $self = {};

    foreach my $annotation_obj (@$annotations_ar) {
        my $full_username = $annotation_obj->full_username;
        my $service       = $annotation_obj->service;
        $self->{lookup}{$full_username}{$service} = $annotation_obj;
    }

    $self->{annotations_ar} = $annotations_ar;

    bless $self, $package;
    return $self;
}

=head1 METHODS

=head2 lookup(RECORD)

Fetch the annotation for a specific user record.

=head3 ARGUMENTS

=over 2

=item B<RECORD> - A Cpanel::UserManager::Record object - The record for which to look up an annotation

=back

=head3 RETURNS

If an annotation matching the full username and service type of the record in question is found, then
it will be returned.

If no match is found, or if the record is not for a service account, then an undefined value is returned.

=cut

# $_[0] = $self
# $_[1] = $record
sub lookup {
    'service' eq $_[1]->type or die 'not a service account';
    return $_[0]->{lookup}{ $_[1]->full_username || die 'no full_username' }{ $_[1]->service || die 'no service' };
}

=head2 lookup_by(FULL_USERNAME, SERVICE)

Fetch the annotation for a specific user and service.

=head3 ARGUMENTS

B<FULL_USERNAME> - string - full name of the user: <user>@<domain> for subaccounts and <user> for cpanel accounts.

B<SERVICE>       - string - name of the service

=head3 RETURNS

If an annotation matching the full username and service type of the record in question is found, then
it will be returned.

If no match is found, or if the record is not for a service account, then an undefined value is returned.

=cut

# $_[0] = $self
# $_[1] = $full_username
# $_[2] = $service
sub lookup_by {
    return $_[0]->{lookup}{ $_[1] }{ $_[2] };
}

=head2 all()

Fetch the complete list of annotations stored.

=head3 RETURNS

array ref - All the annotations available.

=cut

sub all {
    my ($self) = @_;
    return $self->{annotations_ar};
}

1;
