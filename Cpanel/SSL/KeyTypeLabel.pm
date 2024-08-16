package Cpanel::SSL::KeyTypeLabel;

# cpanel - Cpanel/SSL/KeyTypeLabel.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::SSL::KeyTypeLabel

=head1 SYNOPSIS

    my $label = Cpanel::SSL::KeyTypeLabel::to_label($type);

=head1 DESCRIPTION

This little module converts a key type (e.g., C<rsa-2048>) to its
human-readable form.

=cut

#----------------------------------------------------------------------

use Cpanel::Imports;

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $str = to_label( $TYPE )

Converts $TYPE (e.g., C<rsa-2048>) to its human-readable form.

=cut

my %_ECDSA_DETAIL = (
    prime256v1 => 'P-256 (prime256v1)',
    secp384r1  => 'P-384 (secp384r1)',
);

sub to_label ($the_type) {
    my ( $type, $detail ) = split m<->, $the_type;

    die _invalid_type_msg($the_type) if !defined $detail;

    $type =~ tr<a-z><A-Z>;

    if ( $type eq 'RSA' ) {
        $detail = locale()->maketext( '[numf,_1]-bit', $detail );
    }
    elsif ( $type eq 'ECDSA' ) {
        $detail = $_ECDSA_DETAIL{$detail} or die _invalid_type_msg($the_type);
    }
    else {
        die "need update? ($the_type)";
    }

    return "$type, $detail";
}

sub _invalid_type_msg ($the_type) {
    return "Invalid key type: “$the_type”";
}

1;
