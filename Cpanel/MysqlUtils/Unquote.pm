# cpanel - Cpanel/MysqlUtils/Unquote.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::MysqlUtils::Unquote;

use strict;
use warnings;

use Cpanel::MysqlUtils::Quote ();

=encoding utf-8

=head1 NAME

Cpanel::MysqlUtils::Unquote

=head1 SYNOPSIS

    use Cpanel::MysqlUtils::Quote ();
    use Cpanel::MysqlUtils::Unquote ();
    my $quoted_text = Cpanel::MysqlUtils::Quote::quote($unquoted);
    my $unquoted_again = Cpanel::MysqlUtils::Unquote::unquote( $quoted_text );

=head1 DESCRIPTION

This module contains various methods to unquote MySQL identifiers.

=head1 FUNCTIONS


=cut

#cf. http://dev.mysql.com/doc/refman/5.5/en/identifiers.html

our ( $QUOTED_IDENTIFIER_REGEXP, $IDENTIFIER_REGEXP );

BEGIN {
    $QUOTED_IDENTIFIER_REGEXP = qr{`(?:``|[\x{0001}-\x{005f}\x{0061}-\x{ffff}])+`};
    $IDENTIFIER_REGEXP        = qr{(?:$QUOTED_IDENTIFIER_REGEXP|(?:[0-9a-zA-Z\x{0080}-\x{ffff}\$_])+)};
}

#NOTE: This regexp must be run with the /x modifier.
our $QUOTED_STRING_REGEXP = q{(?^x:
    '
    (?:
        ''              #this must be first!
        |
        [^\\\\']*       #anything but a backslash or quote
        (?:
            \\\\.       #backslash plus anything
            [^\\\\']*   #anything but a backslash or quote
        )*
    )*
    '
)};

=head2 unquote( SCALAR )

This function removes beginning or trailing quote characters (' or ") from a scalar.
It should be the opposite of Cpanel::MysqlUtils::Quote::quote.

=head3 Arguments

=over 4

=item $copy - SCALAR - A scalar value that needs to be unquoted.

=back

=head3 Returns

This function returns an unquoted scalar value.

=cut

sub unquote {
    my ($copy) = @_;

    return undef if !$copy;

    if ($copy) {
        return undef if $copy eq 'NULL';
    }

    _unquote_quotes($copy) if $copy =~ tr/'"//;    # operates on $copy

    # No unsafe characters, and we already removed
    # the ' or " so we can stop here
    return $copy if $copy !~ tr{)(A-Za-z0-9_.-}{}c;

    Cpanel::MysqlUtils::Quote::quote_init();
    #
    # This may not seem right at first glance, however
    # unquote uses the NOT !Cpanel::MysqlUtils::Quote::UNQUOTE_PATTERN_REGEXP_PART path for removing
    # slashes to match mysql's behavior instead of Cpanel::MysqlUtils::Quote::UNQUOTE_REGEXP_PART
    #
    $copy =~ s{\\([^$Cpanel::MysqlUtils::Quote::UNQUOTE_PATTERN_REGEXP_PART]{1})}{$1}og;
    #
    $copy =~ s{\\([$Cpanel::MysqlUtils::Quote::UNQUOTE_REGEXP_PART]{1})}{$Cpanel::MysqlUtils::Quote::UNQUOTE_ORIGINAL_CHARACTER{$1}}og;

    return $copy;
}

=head2 unquote_pattern( SCALAR )

This function removes beginning or trailing quote characters (' or ") from a scalar. And unescapes escaped characters.
It should be the opposite of Cpanel::MysqlUtils::Quote::quote_pattern.

=head3 Arguments

=over 4

=item $copy - SCALAR - A scalar value that needs to be unquoted.

=back

=head3 Returns

This function returns an unquoted scalar value.

=cut

sub unquote_pattern {
    my ($copy) = @_;

    return undef if $copy eq 'NULL';

    _unquote_quotes($copy) if $copy =~ tr/'"//;    # operates on $copy

    # No unsafe characters, and we already removed
    # the ' or " so we can stop here
    return $copy if $copy !~ tr{)(A-Za-z0-9_.-}{}c;

    Cpanel::MysqlUtils::Quote::quote_init();
    $copy =~ s{\\([^$Cpanel::MysqlUtils::Quote::UNQUOTE_PATTERN_REGEXP_PART]{1})}{$1}og;
    $copy =~ s{\\([$Cpanel::MysqlUtils::Quote::UNQUOTE_PATTERN_REGEXP_PART]{1})}{$Cpanel::MysqlUtils::Quote::UNQUOTE_ORIGINAL_CHARACTER{$1}}og;

    return $copy;
}

=head2 unquote_identifier( SCALAR )

This function removes beginning or trailing 'grave accent' characters (backticks `).
This should be the opposite of Cpanel::MysqlUtils::Quote::quote_identifier

=head3 Arguments

=over 4

=item $copy - SCALAR - A scalar value that represents an identifier that needs to be unquoted.

=back

=head3 Returns

This function returns an unquoted scalar value.

=cut

sub unquote_identifier {
    my ($copy) = @_;

    return undef if !defined $copy;
    if ( index( $copy, '`' ) == 0 ) {
        substr( $copy, 0, 1, '' );
        substr( $copy, -1, 1, '' ) if rindex( $copy, '`' ) == ( length($copy) - 1 );
        $copy =~ s{``}{`}g if index( $copy, '`' ) > -1;
    }

    return $copy;
}

=head2 unquote_pattern_identifier( SCALAR )

This function removes beginning or trailing 'grave accent' characters (backticks `) and unescapes some special characters.
This should be the opposite of Cpanel::MysqlUtils::Quote::quote_pattern_identifier

=head3 Arguments

=over 4

=item $copy - SCALAR - A scalar value that represents an identifier that needs to be unquoted.

=back

=head3 Returns

This function returns an unquoted scalar value.

=cut

sub unquote_pattern_identifier {
    my ($copy) = @_;
    return undef if $copy eq 'NULL';

    if ( index( $copy, '`' ) == 0 ) {
        substr( $copy, 0, 1, '' );
        substr( $copy, -1, 1, '' ) if rindex( $copy, '`' ) == ( length($copy) - 1 );
        $copy =~ s{``}{`}g  if index( $copy, '`' ) > -1;
        $copy =~ s{\\_}{_}g if index( $copy, '\\_' ) > -1;
        $copy =~ s{\\%}{%}g if index( $copy, '%' ) > -1;
    }
    return $copy;
}

sub _unquote_quotes {

    # Operates on $_[0] for speed as we have already
    # made a copy

    #Do it like this because a string without quotes might have a final
    #(escaped) single quote.
    if ( index( $_[0], q{'} ) == 0 ) {
        substr( $_[0], 0, 1, '' );
        substr( $_[0], -1, 1, '' ) if rindex( $_[0], q{'} ) == ( length( $_[0] ) - 1 );
        $_[0] =~ s{''}{'}g if index( $_[0], q{'} ) > -1;
    }
    elsif ( index( $_[0], q{"} ) == 0 ) {
        substr( $_[0], 0, 1, '' );
        substr( $_[0], -1, 1, '' ) if rindex( $_[0], q{"} ) == ( length( $_[0] ) - 1 );
        $_[0] =~ s{""}{"}g if index( $_[0], q{"} ) > -1;
    }

    return;
}

1;
