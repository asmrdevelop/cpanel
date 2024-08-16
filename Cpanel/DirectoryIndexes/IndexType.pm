# cpanel - Cpanel/DirectoryIndexes/IndexType.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::DirectoryIndexes::IndexType;

use cPstrict;

use Cpanel::ArrayFunc ();    # PPI USE OK - its actually used, but cplint does not understand it.
use Cpanel::Exception ();

=head1 MODULE

C<Cpanel::DirectoryIndexes::IndexType>

=head1 DESCRIPTION

C<Cpanel::DirectoryIndexes::IndexType> provides helpers for translating between
the string format used by UAPI and the internal storage format that cPanel API 1
functions use to represent the index type.

=head1 SYNOPSIS

  use Cpanel::DirectoryIndexes::IndexType ();
  my $got = Cpanel::DirectoryIndexes::IndexType::internal_to_external(0);
  print $got; # should be 'disabled'

=cut

my @INDEX_TYPES = qw/
  inherit
  disabled
  standard
  fancy
  /;

=head1 FUNCTIONS

=head2 internal_to_external(INTERNAL)

=head3 ARGUMENTS

=over

=item INTERNAL - number

The internal representation for index type from API1.

=back

=head3 RETURNS

=over

=item string

One of four possible values:

=over

=item inherit

This directory has no explicit setting and will inherit the server's default.

=item disabled

Directory indexes are disabled.

=item standard

Directory indexes are enabled.

=item fancy

Directory indexes are enabled and configured to be Fancy
l<http://httpd.apache.org/docs/trunk/mod/mod_autoindex.html#IndexOptions>

=back

=back

=head3 THROWS

=over

=item When the internal type is not recognized.

=back

=cut

sub internal_to_external ($internal_type) {
    die Cpanel::Exception::create( 'MissingParameter', ['internal_type'] ) if !defined $internal_type;
    die 'Out of range'                                                     if $internal_type < -1 or $internal_type > 2;

    # $type has a range of -1..2, we normalize to 0..3
    my $type = $INDEX_TYPES[ $internal_type + 1 ];
    if ( !defined $type ) {
        die Cpanel::Exception::create(
            'Unsupported',
            'The “[_1]” type is not supported. The recognized internal types are: [list_or_quoted,_2].',
            [ $internal_type, [ -1 .. 2 ] ]
        );
    }
    return $type;
}

=head2 external_to_internal(TYPE)

=head3 ARGUMENTS

=over

=item TYPE - string

One of the following: inherit, disabled, standard, fancy

=back

=head3 RETURNS

=over

=item number

In the range -1 .. 2

=back

=head3 THROWS

=over

=item When the passed in type cannot be found in the supported list of types.

=back

=cut

sub external_to_internal ($type) {
    die Cpanel::Exception::create( 'MissingParameter', ['type'] ) if !defined $type;

    my $internal_type = Cpanel::ArrayFunc::first( sub { $INDEX_TYPES[$_] eq $type }, 0 .. $#INDEX_TYPES );
    if ( !defined $internal_type ) {
        die Cpanel::Exception::create(
            'InvalidParameter',
            'The “[_1]” argument may only have a value of [list_or_quoted,_2].',
            [ 'type', \@INDEX_TYPES ]
        );
    }
    $internal_type--;    #Convert 0..3 into -1..2, since that's what setindex expects.
    return $internal_type;
}

1;
