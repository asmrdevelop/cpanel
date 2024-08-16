package Cpanel::Exception::DNS::InvalidZoneFile;

# cpanel - Cpanel/Exception/DNS/InvalidZoneFile.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Exception::DNS::InvalidZoneFile

=head1 DISCUSSION

An exception class that represents a DNS zone file parse that returned
errors.

=head1 ARGUMENTS

This class expects:

=over

=item * C<by_line> - An arrayref of 2-member arrayrefs (line, message).
Line numbers are 0-indexed.

=back

=head1 LINE NUMBERS

Line numbers in the exception message are 1-indexed, whereas the metadata’s
C<by_line> is 0-indexed.

=cut

#----------------------------------------------------------------------

use Cpanel::Imports;

use parent qw( Cpanel::Exception::InvalidParameter );

use Cpanel::LocaleString ();

#----------------------------------------------------------------------

sub _default_phrase ( $self, $mt_args_ar ) {
    my $by_line_ar = $self->get_by_line_utf8();

    my @errs = map { locale()->maketext( 'Line [numf,_1]', 1 + $_->[0] ) . ": $_->[1]" } @$by_line_ar;

    return Cpanel::LocaleString->new( 'The [asis,DNS] zone file is invalid. ([comment,reasons for invalidity][join,; ,_1])', \@errs );
}

#----------------------------------------------------------------------

=head1 METHODS

=head2 $line_msg_ar = I<OBJ>->get_by_line_utf8()

Returns the internal C<by_line> attribute with each of the messages
munged so that any non-UTF-8 sequences are escaped.

=cut

sub get_by_line_utf8 ($self) {
    local ( $@, $! );
    require Cpanel::UTF8::Munge;

    my $by_line = $self->get('by_line') or die 'need by_line!';

    my @munged = map {
        my @copy = @$_;

        $copy[1] = Cpanel::UTF8::Munge::munge( $copy[1] );

        \@copy;
    } @$by_line;

    return \@munged;
}

1;
