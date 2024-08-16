package Locale::Maketext::Utils::Phrase::Norm::EndPunc;

use strict;
use warnings;

sub normalize_maketext_string {
    my ($filter) = @_;

    my $string_sr = $filter->get_string_sr();

    if ( ${$string_sr} !~ m/[\!\?\.\:\]…]$/ ) {    # ? TODO ? smarter check that is is actual bracket notation and not just a string ?
        if ( !__is_title_case( ${$string_sr} ) ) {

            # ${$string_sr} = ${$string_sr} . "[comment,missing puncutation ?]";
            $filter->add_warning('Non title/label does not end with some sort of punctuation or bracket notation.');
        }
    }

    return $filter->return_value;
}

my %LOWERCASE_WORD = map { $_ => 1 } qw(
  a
  an
  and
  at
  but
  by
  for
  in
  nor
  of
  on
  or
  so
  the
  to
  up
  yet
);

# Use the AP Style Title Case rules: https://www.bkacontent.com/how-to-correctly-use-apa-style-title-case/
sub __is_title_case {
    my ($string) = @_;

    # Split the string into words.  Notably, check both of the words in a
    # slashed phrase, like "Database/User".  Also, the input string already
    # passed through the Whitespace filter.
    my @words = grep { length $_ } split m{[/ ]|\xc2\xa0}, $string;

    # The first and last words should be uppercase.
    my $first = shift @words;
    return if $first !~ m/^[A-Z\[]/;

    return 1 if !@words;    # No more words to check.
    my $last = pop @words;
    return if $last !~ m/^[A-Z\[]/;

    # Every other word that isn't in our lowercase list should be uppercase.
    foreach (@words) {
        my $key = lc($_);
        return if !m/^[A-Z\[]/ && !$LOWERCASE_WORD{$key};
    }

    return 1;
}

1;

__END__

=encoding utf-8

=head1 Normalization

We want to make sure phrases end correctly and consistently.

=head2 Rationale

Correct punctuation makes the meaning clearer to end users.

Clearer meaning makes it easier to make a good translation.

Consistent punctuation makes it easier for developers to work with.

Consistent punctuation is a sign of higher quality product.

Missing punctuation is a sign that partial phrases are in use or an error has been made.

=head1 IF YOU USE THIS FILTER ALSO USE …

… THIS FILTER L<Locale::Maketext::Utils::Phrase::Norm::Whitespace>.

This is not enforced anywhere since we want to assume the coder knows what they are doing.

=head1 possible violations

None

=head1 possible warnings

=over 4

=item Non title/label does not end with some sort of punctuation or bracket notation.

Problem should be self explanatory. Ending punctuation is not !, ?, ., :, bracket notation, or an ellipsis character.

If it is legit you could address this by adding a [comment] to the end for clarity and to make it harder to use as a partial phrase.

   For some reason I must not end well[comment,no puncuation because …]

If it is titlecase and it has word longer than 2 characters that must start with a lower case letter you have 2 options:

=over 4

=item 1 use asis()

    Buy [asis,aCme™] Products

=item 2 use comment() with a comment that does not have a space or a non-break space:

    People [comment,this-has-to-start-with-lowercase-because-…]for Love

=back

=back

=head1 Entire filter only runs under extra filter mode.

See L<Locale::Maketext::Utils::Phrase::Norm/extra filters> for more details.
