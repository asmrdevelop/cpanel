package Cpanel::StringFunc::SplitBreak;

# cpanel - Cpanel/StringFunc/SplitBreak.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

my $comma_regex;

#######################################
# Split a string and with quoted values
#  Ex:
#  my $str = 'bob,sue,"frank,dave",sam';
#  safesplit(',',$str) would be
#  (
#            'bob',
#            'sue',
#            'frank,dave',
#            'sam'
#  );
#######################################
sub safesplit {

    # Test changes to this routine with x3/parsetag_test.html (Case 32658 #BugEvent.240437)
    my @sp;
    my $regex = $_[0] eq ',' && defined $comma_regex ? $comma_regex : qr{
       (?=.)  # This zero width positive look ahead assertion is necessary to avoid spurious empty item at the end of @sp

       (                #$1: The entire expression between separators, whether quoted or not, including trailing space and quotes if quoted
         (?:
	    \s*
	    (["'])          #$2: The beginning quote
	    (               #$3: Everything excluding the quote character, unless it's backslash-escaped.
	      (?:
             \\\2|[^\2]
	      )*?
	    )
	    \2              # The closing quote
	 )?
	 ([^\Q$_[0]\E]*)    #$4: A non-quoted value: Anything excluding the separator. Same as $1 when text is non-quoted.
       )
       (?:\Q$_[0]\E)?
    }xs;

    $comma_regex = $regex if $_[0] eq ',' && !defined $comma_regex;    #most common caller

    if ( length $_[1] < 3096 ) {
        my @results = $_[1] =~ m/$regex/g;

        @sp = map { ( defined $results[ $_ * 4 + 2 ] ? $results[ $_ * 4 + 2 ] : $results[ $_ * 4 ] ) } ( 0 .. $#results / 4 );
    }
    else {
        while ( $_[1] =~ m/$regex/g ) {
            push @sp, defined $3 ? $3 : $1;
        }
    }

    # TODO: test pop @sp instead of zero width positive look ahead assertion
    # IE Is there an empty item under 100% of circumstances? Is it faster or otherwise "cheaper"?

    return @sp;
}

################################################################################
# This subroutine splits a string into tokens with $width size. The last token
# is less than or equal to $width size.
################################################################################
sub _word_split {
    my ( $text, $width ) = @_;
    return if ( !$width || !$text );

    $width = int($width);
    return if ( $width <= 0 );

    # split the string into $width pieces (last token will be <= $width long)
    my $template = ( 'A' . $width ) x ( length($text) / $width ) . ' A*';
    my @tokens   = unpack( $template, $text );

    # unpack will return an empty token as last token if the 2'nd last token was exactly $width
    # long, so we need to pop the last element if it's empty
    if ( $tokens[-1] eq '' ) {
        pop @tokens;
    }
    return @tokens;
}

################################################################################
# This subroutine breaks a long string by adding a space at each max_column_width
################################################################################
sub textbreak {
    my $text             = shift;
    my $max_column_width = 60;
    my $new_text         = '';

    # reset the matching position
    pos $text = 0;

    # match until the matching position is past the last char
    while ( pos $text < length $text ) {

        # process white space (add them to $new_text as is)
        if ( $text =~ m{ \G ([\s]+) }gcxms ) {
            $new_text .= $1;
        }

        # process non-whitespace
        elsif ( $text =~ m{ \G ([\S]+) }gcxms ) {
            $new_text .= join( ' ', _word_split( $1, $max_column_width ) );
        }
    }
    return $new_text;
}

################################################################################
# This subroutine inserts blank spaces up to width in each line
################################################################################
sub spacedjoin {
    my $width = shift;
    $width--;
    return join( ' ', map { length($_) < $width ? $_ . ( " " x ( $width - length($_) ) ) : $_ } @_ );
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
