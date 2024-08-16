package Cpanel::ZoneFile::LineEdit::Backend;

# cpanel - Cpanel/ZoneFile/LineEdit/Backend.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::ZoneFile::LineEdit::Backend

=head1 SYNOPSIS

XXXX

=head1 DESCRIPTION

XXXX

=cut

#----------------------------------------------------------------------

BEGIN {
    local $SIG{'__WARN__'} = sub { };

    require DNS::LDNS;
    require DNS::LDNS::RR;
    require DNS::LDNS::RData;
}

use Carp ();

use Cpanel::Exception ();

use constant _RECORD_CLASS => 'IN';

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $str = build_line( $NAME, $TTL, $TYPE, @DATA )

Builds a string that encodes a new zone record. The string is suitable
for inclusion into a zone file and will consist of a single line of
ASCII text.

Certain normalizations (e.g. adding final periods to NS record values)
also happen.

Certain values in certain record types (e.g., all @DATA for TXT records)
are DNS “character-strings”; such values will be escaped and quoted as
part of this to ensure that the output is valid ASCII.

=cut

my %ENCODE_ALL_VALUES = (
    TXT        => undef,
    HINFO      => undef,
    X25        => undef,
    ISDN       => undef,
    'NSAP-PTR' => undef,
    GPOS       => undef,
);

sub build_line ( $name, $ttl, $rtype, @value ) {

    _validate_name($name);

    if ( !DNS::LDNS::rr_type_by_name($rtype) ) {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a valid [asis,DNS] resource record type.', [$rtype] );
    }

    if ( $ttl =~ tr<0-9><>c ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'Time-To-Live (TTL) values must be positive integers, not “[_1]”.', [$ttl] );
    }

    # It would be nice to get this from LDNS somehow.
    # The various “_wireformat” constants in LDNS’s rr.c give
    # which parts of different record types are character strings,
    # but LDNS’s API doesn’t seem to expose that information.
    #
    if ( $rtype eq 'CAA' ) {
        _quote_cstring() for $value[2];
    }
    elsif ( $rtype eq 'NAPTR' ) {
        _quote_cstring() for @value[ 2, 3, 4 ];
    }
    elsif ( exists $ENCODE_ALL_VALUES{$rtype} ) {
        _quote_cstring() for @value;
    }

    if ( $rtype eq 'MX' ) {
        _validate_mx( $name, $ttl, @value );
    }

    if ( $rtype eq 'SOA' ) {

        # If we give SOA mname and rname values without a trailing dot to
        # LDNS, then LDNS will postfix the record’s dname. We don’t want
        # that, so let’s avoid it.
        #
        for my $dns_name ( @value[ 0, 1 ] ) {
            if ( '.' ne substr( $dns_name, -1 ) ) {
                $dns_name .= '.';
            }
        }
    }

    my $vindex;
    for my $v (@value) {
        $vindex++;

        if ( $v =~ tr<\x20-\x7e><>c ) {
            require Cpanel::UTF8::Munge;
            $v = Cpanel::UTF8::Munge::munge($v);
            die Cpanel::Exception::create( 'InvalidParameter', "You gave “[_1]” as “[_2]” record data item #[numf,_3]. This value must contain only printable [asis,ASCII] characters.", [ $v, $rtype, $vindex ] );
        }
    }

    my $try_txt = join( "\t", $name, $ttl, _RECORD_CLASS, $rtype, @value );

    # cf. https://rt.cpan.org/Public/Bug/Display.html?id=134402
    utf8::downgrade($try_txt);

    my $rr = DNS::LDNS::RR->new($try_txt);

    if ( !$rr ) {
        my $errstr = DNS::LDNS::errorstr_by_id($DNS::LDNS::last_status);
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” does not form a valid [asis,DNS] resource record. ([_2])', [ $try_txt, $errstr ] );
    }

    my $str = $rr->to_string();
    chomp $str;

    return $str;
}

sub _quote_cstring {
    s<([\x00-\x1f\x7f-\xff"\\])><sprintf('\\%03d', ord $1)>eg;
    substr( $_, 0, 0, q<"> );
    $_ .= q<">;

    return;
}

sub _validate_name ($specimen) {
    die "Contains a malformed wildcard name: $specimen" if $specimen =~ /.\*|\*[^.]/;
    die "Contains a malformed DNS label: $specimen"     if !_looks_like_labels($specimen);

    return;
}

sub _validate_mx ( $name, $ttl, @value ) {
    if ( @value != 2 ) {
        my $num = @value;
        Carp::croak("MX record values have exactly 2 parts, not $num.");
    }

    my %record = (
        name       => $name,
        ttl        => $ttl,
        class      => _RECORD_CLASS,
        type       => 'MX',
        preference => $value[0],
        exchange   => $value[1],
    );

    require Whostmgr::DNS;
    my ( $result, $msg ) = Whostmgr::DNS::sanitize_record( \%record );

    if ( !$result ) {
        Carp::croak("Invalid MX entry: $msg");
    }

    return;
}

# This is intentionally very permissive.
sub _looks_like_labels ($name) {

    $name =~ s/(;.*|\$TTL\s.*)$//;

    return 1 if $name eq '*';
    return 1 if $name =~ /\A(\*\.)?([a-zA-Z0-9_-]+\.)*([a-zA-Z0-9_-]+)\.?\z/;
    return 1 if $name =~ /\A\s*\z/;                                             # comment or TTL
    return 1 if $name =~ /\A[0-9.]+\/[0-9]+\z/;                                 # cidr notation
    return 0;
}

1;
