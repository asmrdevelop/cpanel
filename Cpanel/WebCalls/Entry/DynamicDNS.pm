package Cpanel::WebCalls::Entry::DynamicDNS;

# cpanel - Cpanel/WebCalls/Entry/DynamicDNS.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::WebCalls::Entry::DynamicDNS

=head1 SYNOPSIS

    my $obj = Cpanel::WebCalls::Entry::DynamicDNS->adopt( \%data );

    printf "user: %s\n", $obj->created_time();

=head1 DESCRIPTION

This class extends L<Cpanel::WebCalls::Entry> for use with dynamic DNS.

=cut

#----------------------------------------------------------------------

use parent 'Cpanel::WebCalls::Entry';

#----------------------------------------------------------------------

=head1 ACCESSORS

=over

=item * C<domain> - Retrieves the entry’s domain.

=item * C<description> - Retrieves the entry’s description.

=back

=cut

sub domain ($self) {
    return $self->{'data'}{'domain'};
}

sub description ($self) {
    return $self->{'data'}{'description'};
}

1;
