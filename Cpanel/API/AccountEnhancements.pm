package Cpanel::API::AccountEnhancements;

# cpanel - Cpanel/API/AccountEnhancements.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf8

=head1 NAME

Cpanel::API::AccountEnhancements

=head1 DESCRIPTION

This module contains UAPI methods related to Account Enhancements.

=head1 FUNCTIONS

=cut

use cPstrict;
use Cpanel::AdminBin::Call ();

my $non_mutating = { allow_demo => 1 };
my $mutating     = {};

our %API = (
    list            => $non_mutating,
    has_enhancement => $non_mutating,
);

=head2 list()

This function lists the Account Enhancements assigned to a user.

=head3 RETURNS

Returns a list of all Account Enhancements assigned to a user.

=cut

sub list ( $args, $result ) {

    my ( $enhancements, $warnings_ref ) = Cpanel::AdminBin::Call::call( 'Cpanel', 'accountenhancements', 'LIST' );
    $result->errors($@) if $@;
    $result->data($enhancements);
    $result->raw_warning($_) for @$warnings_ref;

    return 1;
}

=head2 has_enhancement()

This function confirms if a user has a specific Account Enhancement assigned to them.

=head3 ARGUMENTS

=over

=item name - string
The name of the Account Enhancement you want to look for.

=back

=head3 RETURNS

Returns 1 if Account Enhancement is found and enabled, otherwise returns 0.

=cut

sub has_enhancement ( $args, $result ) {

    my $id = $args->get_length_required('id');
    my ( $enhancements, $warnings ) = Cpanel::AdminBin::Call::call( 'Cpanel', 'accountenhancements', 'LIST' );
    my $enhancement_found = 0;

    foreach my $ae ( @{$enhancements} ) {
        if ( $ae->{'id'} eq $id ) {
            $enhancement_found = 1;
            last;
        }
    }
    $result->data($enhancement_found);
    $result->errors($@) if $@;
    $result->raw_warning($_) for @$warnings;

    return 1;
}

1;
