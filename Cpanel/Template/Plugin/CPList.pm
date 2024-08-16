package Cpanel::Template::Plugin::CPList;

# cpanel - Cpanel/Template/Plugin/CPList.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

Cpanel::Template::Plugin::CPList

=cut

use base 'Template::Plugin';
use Cpanel::JSON      ();
use Scalar::Util      ();
use Template::Filters ();

BEGIN {
    *_stringify = \&Cpanel::JSON::SafeDump;
}

sub load {
    my ( $class, $context ) = @_;

    #ungrep: SELECT LIST ITEMS THAT DO *NOT* MATCH A GIVEN STRING
    #CAN'T SEE A WAY TO WRAP THIS AROUND THE ORIGINAL
    #Template::VMethods::list_grep, SO WE DUPLICATE CODE...:(
    $context->define_vmethod( 'list', 'ungrep', \&_ungrep );

    #ofeach: RETURN A LIST OF THE VALUES MATCHING THE GIVEN KEY/INDEX.
    #THIS ASSUMES THAT EACH ELEMENT OF THE ARRAY IS AN ARRAY, HASH, OR OBJECT.
    $context->define_vmethod( 'list', 'ofeach', \&_ofeach );

    #sum: ADDS ALL LIST VALUES
    $context->define_vmethod( 'list', 'sum', \&_sum );

    #transform: Encode the items in the list.
    $context->define_vmethod(
        'array',
        'encode',
        \&encode,
    );

    return $class;
}

sub _ungrep {
    my ( $list, $pattern ) = @_;
    $pattern ||= '';

    return [ grep { $_ !~ m/$pattern/ } @{$list} ];
}

sub _ofeach {
    my ( $list, $attr ) = @_;
    my @retval;

    if ( ref $list->[0] eq 'HASH' ) {
        @retval = map { $_->{$attr} } @$list;
    }
    elsif ( ref $list->[0] eq 'ARRAY' ) {
        @retval = map { $_->[$attr] } @$list;
    }
    elsif ( Scalar::Util::blessed $list->[0] ) {
        if ( $list->[0]->can($attr) ) {    #METHOD
            @retval = map { $_->$attr() } @$list;
        }
        else {
            @retval = map { $_->{$attr} } @$list;
        }
    }

    return \@retval;
}

sub _sum {
    my $list = shift;
    my $sum  = 0;
    $sum += $_ foreach @{$list};
    return $sum;
}

=head2 Function: encode

Encodes the items the list of strings into a new list of strings applying the encoding
rule to each element.  Will just copy it as is if the encoding rule is not recognized.

Arguments:

=over

=item $list

=item $rule

One of "html", "xml", "url", "uri", "json", "".  If undefined, it will default to html encoding.

=back

Returns:

Return the new list with each item encoded

=cut

sub encode {
    my ( $list, $rule ) = @_;

    # initialize the arguments not set
    $rule = "html" if !length $rule;

    # determine which filter function to use if any
    my $transform_ref;
    if ( $rule eq "html" ) {
        $transform_ref = \&Template::Filters::html_filter;
    }
    elsif ( $rule eq "url" ) {
        $transform_ref = \&Template::Filters::url_filter;
    }
    elsif ( $rule eq "uri" ) {
        $transform_ref = \&Template::Filters::uri_filter;
    }
    elsif ( $rule eq "xml" ) {
        $transform_ref = \&Template::Filters::xml_filter;
    }
    elsif ( $rule eq "json" ) {
        $transform_ref = \&_stringify;
    }
    else {
        undef $transform_ref;
    }

    # transform the string
    my @items;
    if ($transform_ref) {
        @items = map { $transform_ref->($_) } @$list;
    }
    else {
        @items = map { $_ } @$list;
    }

    return \@items;
}

1;
