package Cpanel::ZoneFile::Search;

# cpanel - Cpanel/ZoneFile/Search.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::ZoneFile::Search

=head1 SYNOPSIS

    # Find all A or AAAA record values for the “www” subdomain:
    my @records = Cpanel::ZoneFile::Search::name_and_types(
        $zone_name,
        'www',
        'A', 'AAAA',
    );

=head1 DESCRIPTION

This module searches a zone file I<without> parsing every RR in the file.

=head1 CAVEATS

This module only finds single-line resource records. It also doesn’t
honor C<$ORIGIN> or C<$INCLUDE> directives. Ideally you should use a
more full-fledged parser like CPAN’s L<Parse::DNS::Zone>, but this module
offers better speed for a narrower use case.

=head1 SEE ALSO

L<Cpanel::ZoneFile::Query> is a more robust version of this module.

=cut

#----------------------------------------------------------------------

use Cpanel::Context ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 @rrs = name_and_types( $ZONE_TEXT, $ORIGIN, $NAME, @TYPES )

Finds records in $ZONE_TEXT that match $NAME and at least one of
@TYPES. $ORIGIN is the zone file’s origin.

Returns a list of L<Net::DNS::RR> instances, one for each
matching record.

This function B<must> be called in list context.

=head3 Example

To find C<www.example.com>’s A and AAAA records in
the C<example.com> zone, do:

    my @rrs = name_and_types( $zonetext, 'example.com', 'www', 'A', 'AAAA' );

=cut

sub name_and_types ( $zonetext, $origin, $name, @types ) {
    Cpanel::Context::must_be_list();

    local $!;

    my $types_join = join '|', @types;

    my $name_re = quotemeta $name;

    if ( '.' ne substr( $name, -1 ) ) {
        my $full_re = quotemeta "$name.$origin.";
        $name_re = "(?:$name_re|$full_re)";
    }

    my $types_re = qr<
        ^
        [ \t]*
        $name_re
        [ \t]+

        # TTL and class are both optional as per RFC 1035
        (?:
            [0-9]+ # ttl
            [ \t]+
            (?:
                [^ \t]+ # class
                [ \t]+
            )?
            |
            [^ \t]+ # class
            [ \t]+
            (?:
                [0-9]+ # ttl
                [ \t]+
            )?
        )?

        (?:$types_join)
        [ \t]
        .+
        $
    >mx;

    return map { _to_rr($_) } ( $zonetext =~ m<($types_re)>g );
}

sub _to_rr ($line) {
    local ( $!, $@ );
    require Net::DNS::RR;
    return Net::DNS::RR->new($line);
}

1;
