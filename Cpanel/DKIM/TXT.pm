package Cpanel::DKIM::TXT;

# cpanel - Cpanel/DKIM/TXT.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::DKIM::TXT - Parses and validates DKIM TXT records

=head1 SYNOPSIS

    use Cpanel::DKIM::TXT;

    my $tags = Cpanel::DKIM::TXT::parse_and_validate( $txt_rdata );

=head1 DESCRIPTION

This module provides a method to parse DKIM TXT record data to break it
down into the expected DKIM tags, validate those tags, and filter out
data that RFC6376 describes as things that should be ignored.

For exact details on the DKIM specification see L<RFC6376|https://tools.ietf.org/html/rfc6376>.

Specifically, the definition of the DKIM TXT record can be found in L<section 3.6.1|https://tools.ietf.org/html/rfc6376#section-3.6.1>.

DKIM parameters are defined in L<IANA's DKIM parameter assignments|https://www.iana.org/assignments/dkim-parameters/dkim-parameters.xhtml>.

=cut

# RFC6376 only specifies that the v tag needs to be first, the rest are arbitrary
my @_TAG_ORDER = qw(v h k n p s t);

my @_HASH_ALGORITHMS = qw(sha256);
my @_KEY_TYPES       = qw(rsa ed25519);
my @_SERVICES        = qw(* email);
my @_FLAGS           = qw(y s);

# cf. https://tools.ietf.org/html/rfc6376#section-3.2
my $FWS_RE  = '(?:[ \t]|\r\n)*';
my $_TAG_RE = qr/
    ([a-zA-Z][a-zA-Z0-9_]*)
    $FWS_RE = $FWS_RE
    ( [^;]*? )
    $FWS_RE
    (?:;|$)
/x;

my %_TRANSLATE = (
    h => \&_translate_hash_algorithm,
    k => \&_translate_key_type,
    p => \&_translate_key,
    s => \&_translate_services,
    t => \&_translate_flags
);

my %_recognized_tags;
@_recognized_tags{@_TAG_ORDER} = ();

=head2 parse_and_validate

Parses and validates a string as a DKIM TXT records specifier

=over 2

=item Input

=over 2

=item C<SCALAR>

The string to parse. Per L<the DKIM specification|https://tools.ietf.org/html/rfc6376#section-3.6.2.2> this B<MUST> be the plain concatenation of the
TXT record’s strings, i.e., with no intervening whitespace or other
characters.

B<TODO:> This function should ideally accept the TXT record’s strings
as a list or array rather than relying on the caller to have implemented
part of the DKIM specification correctly.

=back

=item Output

=over 2

=item C<HASHREF>

Returns a C<HASHREF> of the tags found in the string.

The keys of the hash are:

=over 2

=item C<v> - DKIM version - C<SCALAR>

If the C<v=> tag is present, and is the first tag present, this key will always
hold the value of C<DKIM1> as defined by RFC6376.

If the C<v=> tag is present and is not the first tag, or is not set to C<DKIM1>,
this method throws an exception.

This key does not exist if no C<v=> tag is present in the input string.

=item C<h> - Hash algorithms - C<ARRAYREF>

If the C<h=> tag is present, it is a colon separated list of allowed hash
algorithms.

As of L<RFC8301|https://tools.ietf.org/html/rfc8301> the only valid value for
the hash algorithm is C<sha256>. Any other values in the the list should be
ignored and are filtered during parsing.

This key does not exist if no C<h=> tag is present in the input string, or if
all of the values specified by the tag are invalid.

The value of this field is an C<ARRAYREF> to support future changes to the
DKIM specification.

=item C<k> - Key type - C<SCALAR>

If the C<k=> tag is present, it defines the type of key used for DKIM
signatures.

The current IANA assignments allow for C<rsa> or C<ed25519> key types.

This key does not exist if no C<k=> tag is present in the input string.

=item C<n> - Notes - C<SCALAR>

If the C<n=> tag is present, it defines notes for the DKIM record.

There is no specification for any format of the notes, and the RFC
indicates they should be used sparingly and only by administrators.

This key does not exist if no C<n=> tag is present in the input string.

=item C<p> - Public Key - C<SCALAR>

The C<p=> tag is the only DKIM tag that is required to be present in the input
string.

This method throws an exception if there is no public key present.

=item C<s> - Services - C<ARRAYREF>

If the C<s=> tag is present, it is a colon separated list of allowed services.

Only C<email> and C<*> are currently defined in the IANA assignments. Any other
values in the list should be ignored and are filtered out during parsing.

This key does not exist if no C<s=> tag is present in the input string, or if
all of the values specified are invalid.

=item C<t> - Flags - C<ARRAYREF>

If the C<t=> tag is present, it is a colon separated list of flags for the
record.

Only C<y> and C<s> are currently defined in the IANA assignments. Any other
values in the list should be ignored and are filtered out during parsing.

This key does not exist if no C<t=> tag is present in the input string, or if
all of the values specified are invalid.

=back

=back

=back

=cut

sub parse_and_validate {

    my ($txt_record) = @_;

    my @found = $txt_record =~ /$_TAG_RE/g;
    my %tags;

    for ( my $i = 0; $i < scalar @found; $i += 2 ) {

        my $tag   = $found[$i];
        my $value = $found[ $i + 1 ];

        next if !exists $_recognized_tags{$tag};

        if ( $tags{$tag} ) {
            require Cpanel::Exception;
            die Cpanel::Exception->create( "The records cannot contain duplicate “[_1]” tags.", [$tag] );
        }

        _validate_version( $value, $i ) if $tag eq 'v';

        $value = $_TRANSLATE{$tag}($value) if $_TRANSLATE{$tag};

        $tags{$tag} = $value if defined $value;
    }

    # The key is required, but it is allowed to be empty to indicate a revoked key
    if ( !defined $tags{p} ) {
        require Cpanel::Exception;
        die Cpanel::Exception->create( "The record requires the “[_1]” tag.", ['p'] );
    }

    if ( $txt_record !~ m<\A (?:$FWS_RE $_TAG_RE $FWS_RE)* \z>xo ) {
        require Cpanel::Exception;
        die Cpanel::Exception->create('The record is not a valid list of [asis,DKIM] tags and values.');
    }

    return \%tags;
}

sub _translate_hash_algorithm {
    my ($h) = @_;
    return _split_and_filter_allowed( $h, \@_HASH_ALGORITHMS );
}

sub _translate_key_type {
    my ($k) = @_;
    return undef if !grep { $_ eq $k } @_KEY_TYPES;
    return $k;
}

sub _translate_key {
    my ($p) = @_;
    $p =~ tr/ //d;
    return $p;
}

sub _translate_flags {
    my ($t) = @_;
    return _split_and_filter_allowed( $t, \@_FLAGS );
}

sub _translate_services {
    my ($s) = @_;
    return _split_and_filter_allowed( $s, \@_SERVICES );
}

sub _validate_version {
    my ( $v, $i ) = @_;

    if ( $i != 0 ) {
        require Cpanel::Exception;
        die Cpanel::Exception->create("The [asis,DKIM] version must be the first tag in the record.");
    }

    if ( $v ne "DKIM1" ) {
        require Cpanel::Exception;
        die Cpanel::Exception->create( "The [asis,DKIM] version must be “[_1]”.", ["DKIM1"] );
    }

    return;
}

sub _split_and_filter_allowed {
    my ( $tag, $allowed ) = @_;

    my @values;

    for my $s ( split / $FWS_RE : $FWS_RE /x, $tag ) {
        push @values, $s if grep { $_ eq $s } @$allowed;
    }

    return scalar @values ? \@values : undef;
}

1
