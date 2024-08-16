package Cpanel::Validate::AnyAllMatcher;

# cpanel - Cpanel/Validate/AnyAllMatcher.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::AnyAllMatcher - Encapsulates logic to determine if any or all is true

=head1 SYNOPSIS

    use Cpanel::AnyAllMatcher;

    my $items    = [qw(item1 item2 item3)];
    my $callback = sub { return 1 if $_[0] eq 'item2' };

    # If 'match' is any, then match(…) is truthy if the callback returns truthy for any of the items
    my $matches_any = Cpanel::AnyAllMatcher::match({ match => 'any', items => $items}, $callback);
    print "$matches_any\n";
    # 1

    # If 'match' is all, then match(…) is truthy if the callback returns truthy for all of the items
    my $matches_all = Cpanel::AnyAllMatcher::match({ match => 'all', items => $items}, $callback);
    print "$matches_all\n";
    # 0

=head1 DESCRIPTION

# longer description...

=cut

=head2 match

=over 2

=item Input

=over 3

=item C<SCALAR> or  C<HASHREF>

If the input is a C<SCALAR>, it is treated as a single item to check

If the input is a C<HASHREF>, it should be in the form of:

    { match: <any|all>, items: ["item1", "item2", … ] }

WHhere:

C<match> - (optional) Determines whether C<all> the items must be true, or C<any> of them. If not specified, it defaults to C<all>.

C<roles> - An C<ARRAYREF> of items to check

=item C<CODEREF>

The C<CODEREF> to determine if each item is true or false, it should take a single item as a parameter and return a boolean result

=back

=item Output

=over 3

Returns 1 if the items are enabled, 0 otherwise

=back

=back

=cut

sub match {

    my ( $args, $callback ) = @_;

    if ( !defined $args ) {
        require Cpanel::Exception;
        die Cpanel::Exception::create( 'MissingParameter', 'No parameter value specified.' );
    }

    if ( !defined $callback ) {
        require Cpanel::Exception;
        die Cpanel::Exception::create( 'MissingParameter', 'No callback specified.' );
    }

    if ( !ref $args ) {
        return $callback->($args) ? 1 : 0;
    }
    elsif ( ref $args eq 'HASH' ) {

        my $match = $args->{match} || 'all';
        my $items = $args->{items};

        if ( $match ne 'any' && $match ne 'all' && $match ne 'none' ) {
            require Cpanel::Exception;
            die Cpanel::Exception::create( 'InvalidParameter', 'The “[_1]” parameter must be “[_2]”, “[_3]” or “[_4]” value.', [qw(match any all none)] );
        }

        if ( !$items || ref $items ne 'ARRAY' ) {
            require Cpanel::Exception;
            die Cpanel::Exception::create( 'InvalidParameter', 'The “[_1]” parameter must be an array reference.', ["items"] );
        }

        foreach my $item (@$items) {
            my $bool = $callback->($item);
            return 1 if $bool  && $match eq 'any';
            return 0 if $bool  && $match eq 'none';
            return 0 if !$bool && $match eq 'all';
        }

        # If we get here, then all of the specified roles are enabled for 'all' or none of them are enabled for 'any'
        return $match eq 'any' ? 0 : 1;
    }

    require Cpanel::Exception;
    die Cpanel::Exception::create( 'InvalidParameter', 'The input parameter must be a string or a hash reference.' );
}

1;
