package Cpanel::StringFunc;

# cpanel - Cpanel/StringFunc.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=head1 NAME

Cpanel::StringFunc - Various string routines

=head1 DESCRIPTION

Contains a variety of string utility functions.  Pretty straight forward.

=head1 SUBROUTINES

=cut

use Cpanel::StringFunc::Case       ();
use Cpanel::StringFunc::Match      ();
use Cpanel::StringFunc::Trim       ();
use Cpanel::StringFunc::File       ();
use Cpanel::StringFunc::SplitBreak ();
use Cpanel::StringFunc::Count      ();
use Cpanel::StringFunc::Replace    ();

our $VERSION = '1.5';

*ToUpper               = *Cpanel::StringFunc::Case::ToUpper;
*ToLower               = *Cpanel::StringFunc::Case::ToLower;
*textbreak             = *Cpanel::StringFunc::SplitBreak::textbreak;
*safesplit             = *Cpanel::StringFunc::SplitBreak::safesplit;
*beginmatch            = *Cpanel::StringFunc::Match::beginmatch;
*ibeginmatch           = *Cpanel::StringFunc::Match::ibeginmatch;
*endmatch              = *Cpanel::StringFunc::Match::endmatch;
*iendmatch             = *Cpanel::StringFunc::Match::iendmatch;
*endtrim               = *Cpanel::StringFunc::Trim::endtrim;
*trim                  = *Cpanel::StringFunc::Trim::trim;
*ltrim                 = *Cpanel::StringFunc::Trim::ltrim;
*rtrim                 = *Cpanel::StringFunc::Trim::rtrim;
*begintrim             = *Cpanel::StringFunc::Trim::begintrim;
*addlinefile           = *Cpanel::StringFunc::File::addlinefile;
*remlinefile           = *Cpanel::StringFunc::File::remlinefile;
*countchar             = *Cpanel::StringFunc::Count::countchar;
*get_curly_brace_count = *Cpanel::StringFunc::Count::get_curly_brace_count;
*regex_rep_str         = *Cpanel::StringFunc::Replace::regex_rep_str;
*regsrep               = *Cpanel::StringFunc::Replace::regsrep;

sub unquotemeta {
    require Cpanel::StringFunc::UnquoteMeta;    # it said do not add deps above...
    goto &Cpanel::StringFunc::UnquoteMeta::unquotemeta;
}

################################################################################
# This subroutine breaks a long string by adding a space at each max_column_width
################################################################################

=head2 indent_string( $string[, $indent_string] )

Indents each single or multi-lined string with the $ident_string.

=over 2

=item Input

=over 4

=item I<scalar> (string)

String for that will be indentend.  If it's a multi-line string, then each
line in the string will also be indented.

=item I<scalar> (string -- optional)

This is the string used to indent each line.  If left undefined, 4 white
spaces will be used instead.

=back

=back

=cut

sub indent_string {
    my ( $string, $indentor ) = @_;
    $string //= '';
    if ( !defined $indentor || $indentor eq '' ) {
        $indentor = '    ';    # four spaces, not \t
    }
    my $chomped = chomp($string);
    $string =~ s{\n}{\n$indentor}g;
    $string .= "\n" if $chomped;    # only append a newline if we removed some whitespace
    return $indentor . $string;
}

1;

__END__

=head1 $1 caveat

Never pass $1 (and company) directly as an argument to anything.

Always send a copy.

It usually just results in unexpected behavior but sometimes can be really bad.

By way of example:

    safesplit(',', $1); # this will hang due to regex voo doo

    safesplit(',',"$1"); # good

    # also good, essentially the same thing
    my $copy = $1;
    safesplit(',', $copy);
