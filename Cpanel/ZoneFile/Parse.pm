package Cpanel::ZoneFile::Parse;

# cpanel - Cpanel/ZoneFile/Parse.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::ZoneFile::Parse

=head1 SYNOPSIS

    my $pieces_ar = Cpanel::ZoneFile::Parse::parse_string_to_b64( $zone_str, 'bob.org' );

… or, if you’re purely internal and don’t care about character encoding
(see below):

    my $pieces_ar = Cpanel::ZoneFile::Parse::parse_string( $zone_str, 'sue.com' );

=head1 DESCRIPTION

This module parses a DNS zone master-file string. It identifies line
comments, control statements (e.g., C<$TTL>), and (of course) resource
records.

=head1 B<BEWARE:> CHARACTER ENCODING

DNS is ancient; therefore, it happily accepts any arbitrary octet sequence.
WHM’s APIs accept such sequences, and customers are able to modify their
own files. Beyond that, zone files’ own escaping syntax provides a way to
encode arbitrary octets even while the zone file itself remains 7-bit ASCII.

Thus, callers that need to represent DNS data as UTF-8 (or some other
non-binary-compatible encoding) need a plan of action for accommodating
such “weirdness”. Notably, this affects anything that needs to JSON-encode
parsed DNS data.

=head1 SEE ALSO

L<Cpanel::ZoneFile::Query> and L<Cpanel::ZoneFile::Search> implement
logic for “querying” a zone file.

=cut

#----------------------------------------------------------------------

BEGIN {

    # Bug in DNS::LDNS: “Subroutine DNS::LDNS::RData::compare redefined”.
    # “no warnings” doesn’t silence it, so we have to discard it.
    # cf. https://rt.cpan.org/Public/Bug/Display.html?id=134388
    local $SIG{'__WARN__'} = sub { };

    require DNS::LDNS;
    require DNS::LDNS::RR;
    require DNS::LDNS::RData;
}

use Cpanel::Autodie                    ();
use Cpanel::TempFH                     ();
use Cpanel::XSLib::File                ();
use Cpanel::ZoneFile::Parse::Constants ();

my $COMMENT_LINE_REGEXP = qr<
    \A
    (?:
        \s* (?: ; | \z )
    )
>x;

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $items_ar = parse_string( $ZONE_STRING, $ORIGIN_DOMAIN )

Parses $ZONE_STRING (a DNS zone master file) with $ORIGIN_DOMAIN as its
origin domain.

The return is an array of hashrefs; each hashref represents one of:

=over

=item * A record in the zone file:

=over

=item * C<line_index> - The 0-index of the line where the record starts.

=item * C<type> - The string C<record>

=item * C<dname> - The record’s owner, with subdomains reduced as per
convention (e.g., C<foo> rather than C<foo.example.com.>).

=item * C<ttl> - A positive integer.

=item * C<record_type> - A string (e.g., C<TXT>)

=item * C<data> - An array of scalars. Each item is:

=over

=item * For character strings: the literal content, as a byte string.

(NB: This is the item’s I<literal> content, free of the zone file’s own
encoding. For example, if the zone file contains C<\255>, here that’s
just a single byte, 0xFF.)

=item * For all others: whatever L<ldns_rdf2str(3)> outputs.

=back

=back

=item * A line of comment:

=over

=item * C<line_index> - The 0-index of the line.

=item * C<type> - The string C<comment>

=item * C<text> - A byte string of the line’s content (no trailing newline).

=back

=item * A control statement. This has the same elements as a line of comment,
but C<type> is C<control>.

=back

B<IMPORTANT:> The output of this function is B<NOT> safe to send to
external systems via text (e.g., JSON) since several of its fields
can contain arbitrary octet sequences.

=cut

sub parse_string ( $zone_string, $origin_name ) {
    return _parse_string( $zone_string, $origin_name );
}

=head2 $items_ar = parse_string_to_b64( $ZONE_STRING, $ORIGIN_DOMAIN )

Same as C<parse_string()> but encodes several fields as base64 and suffixes
their hash keys with C<_b64>. Specifically:

=over

=item * C<dname> becomes C<dname_b64>.

=item * C<data> becomes C<data_b64>.

=item * C<text> becomes C<text_b64>.

=back

This is important for sending JSON to external systems (e.g., via the
API) since all JSON text must be valid UTF-8, and zone files can contain
arbitrary octet sequences.

=cut

sub parse_string_to_b64 ( $zone_string, $origin_name ) {
    local ( $@, $! );
    require Cpanel::Base64;

    return _parse_string( $zone_string, $origin_name, \&Cpanel::Base64::encode_to_line, '_b64' );
}

sub _parse_string ( $zone_string, $origin_name, $rdata_xform = undef, $xform_suffix = q<> ) {    ## no critic qw(ManyArgs) - mis-parse
    $origin_name .= '.' if '.' ne substr( $origin_name, -1 );

    # Workaround for https://rt.cpan.org/Public/Bug/Display.html?id=134402
    utf8::downgrade($origin_name);

    my $origin = DNS::LDNS::RData->new( DNS::LDNS::LDNS_RDF_TYPE_DNAME(), $origin_name );
    my $prev   = $origin->clone;
    my $ttl    = 0;
    my $count  = 0;

    # Start at line 1
    my $line = 0;

    local $DNS::LDNS::last_status = 0;
    local $DNS::LDNS::last_error  = q<>;
    local $DNS::LDNS::line_nr;

    # Ensure there's a trailing newline; if it's missing then that
    # messes up our logic below.
    $zone_string .= "\n" if substr( $zone_string, -1 ) ne "\n";

    my @file_lines = split m<\n>, $zone_string, -1;

    # Ignore a final newline:
    pop @file_lines if $file_lines[-1] eq q<>;

    my @contents;

    # Unfortunately LDNS doesn’t seem to expose a means of parsing a zone
    # as a single string; it has to read it from a file.
    my $fh = Cpanel::TempFH::create();
    Cpanel::Autodie::syswrite_sigguard( $fh, $zone_string );
    Cpanel::Autodie::sysseek( $fh, 0, 0 );

    # Sanity-check:
    die 'PANIC: Already done?!?' if _ldns_is_done_reading($fh);

    my $last_tell = _ldns_file_location($fh);

    while ( !_ldns_is_done_reading($fh) ) {
        my $rr = DNS::LDNS::RR->new(
            file        => $fh,
            default_ttl => \$ttl,
            origin      => \$origin,
            prev        => \$prev,
        );

        if ( !exists $Cpanel::ZoneFile::Parse::Constants::EXPECTED_STATUS{$DNS::LDNS::last_status} ) {
            my $errstr = DNS::LDNS::errorstr_by_id($DNS::LDNS::last_status);

            $line++;

            die "Failed to parse DNS zone (at or after line $line): $errstr";
        }

        my $post_tell = _ldns_file_location($fh);

        # Ideally $DNS::LDNS::line_nr should indicate the number of lines
        # read in the most recent read, but $line_nr appears to be buggy
        # as of April 2021. Until that’s fixed we’ll avoid its use here;
        # thankfully we can achieve the same effect by querying the
        # filehandle directly.
        #
        # Bug reported: https://github.com/NLnetLabs/ldns/issues/129

        my $lines_delta = substr( $zone_string, $last_tell, $post_tell - $last_tell ) =~ tr<\n><>;
        $last_tell = $post_tell;

        my $end_line = $line + $lines_delta;

        for my $linenum ( $line .. ( $end_line - 1 ) ) {

            # Whether we got a record or not, we need to look for non-RR
            # lines. That’s fairly easy: anything that starts with a
            # semicolon, space-then-semicolon, or a dollar-sign.
            # (We’re assuming here that the zone file is valid.)
            #
            if ( $file_lines[$linenum] =~ $COMMENT_LINE_REGEXP ) {

                my $line = $file_lines[$linenum];

                if ( length $line ) {
                    push @contents, _hashify_comment( $line, $rdata_xform, $xform_suffix );
                    $contents[-1]{'line_index'} = $linenum;
                }
            }
            else {
                # We got here because LDNS found exactly 1 RR or exactly
                # 1 control line, and we found a non-comment line. Thus,
                # there are no more comments.

                if ($rr) {
                    push @contents, _hashify_rr( $origin_name, $rr, $rdata_xform, $xform_suffix );
                    $contents[-1]{'line_index'} = $linenum;
                }
                else {

                    # We found a control (e.g., $TTL).
                    #
                    # We could differentiate the controls (e.g., type='ttl'),
                    # but that would seem to entail more manual parsing of the
                    # zone, which currently we don’t do. If needed we can
                    # augment the hashref created below with, e.g., “subtype”
                    # and parse information.

                    my $line = $file_lines[$linenum];

                    if ($rdata_xform) {
                        $line = $rdata_xform->($line);
                    }

                    push @contents, {
                        line_index          => $linenum,
                        type                => 'control',
                        "text$xform_suffix" => $line,
                    };
                }

                last;
            }
        }

        $line = $end_line;
    }

    return \@contents;
}

sub _ldns_is_done_reading ($fh) {

    # LDNS itself, when it parses a zone file, checks C’s feof() to know
    # when it’s at the end of a zone file. (As of April 2021, anyhow.)

    return Cpanel::XSLib::File::feof($fh);
}

sub _ldns_file_location ($fh) {

    # As with _ldns_is_done_reading(): ideally DNS::LDNS would expose
    # something like this so we wouldn’t depend on Perl’s tell() being
    # a wrapper around ftell(3). But this works for now.

    return Cpanel::XSLib::File::ftell($fh);
}

sub _hashify_comment ( $line, $rdata_xform, $xform_suffix ) {
    if ($rdata_xform) {
        $line = $rdata_xform->($line);
    }

    return {
        type                => 'comment',
        "text$xform_suffix" => $line,
    };
}

sub _hashify_rr ( $origin_name, $rr, $rdata_xform, $xform_suffix ) {    ## no critic qw(ManyArgs) - mis-parse
    my @rdata_txt = map { _get_rdata_str( $rr->rdata($_) ) } ( 0 .. $rr->rd_count() - 1 );

    if ($rdata_xform) {
        $_ = $rdata_xform->($_) for @rdata_txt;
    }

    my $dname = $rr->dname();
    _unescape() for $dname;

    $dname =~ s<\.\Q$origin_name\E\z><>;

    return {
        type                 => 'record',
        "dname$xform_suffix" => $rdata_xform ? $rdata_xform->($dname) : $dname,
        ttl                  => $rr->ttl(),
        record_type          => DNS::LDNS::rr_type2str( $rr->type() ),
        "data$xform_suffix"  => \@rdata_txt,
    };
}

# DNS::LDNS lacks this as of Feb 2020.
# (CAA records use it.)
use constant _LDNS_RDF_TYPE_LONG_STR => 35;

sub _get_rdata_str {
    my $obj = shift;

    my $val = $obj->to_string();

    my $type = $obj->type();

    # DNS::LDNS doesn’t currently expose a method to fetch the raw data
    # from an RData object. We could patch it if that’s gainful.
    #
    if ( grep { $_ == $type } DNS::LDNS::LDNS_RDF_TYPE_STR(), _LDNS_RDF_TYPE_LONG_STR ) {
        chop $val;
        substr( $val, 0, 1, q<> );

        _unescape() for $val;
    }

    return $val;
}

sub _unescape {
    s<\\([0-9]{3}|[^0-9])><
        (1 == length $1) ? $1 : chr($1)
    >eg;

    return;
}

1;
