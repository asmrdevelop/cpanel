package Cpanel::DnsUtils::RR;

# cpanel - Cpanel/DnsUtils/RR.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::Regex ();

our $MAX_TXT_LENGTH = 255;

# RFC 1035 says to quote anything that has a space.
# It is not necessary to quote under any other circumstances as long as we
# escape q{"}.
#
# Escaping newline, carriage returns. Also "'", "@" and ";". These should
# be save in the quoted chunks but we escape them nonetheless just to be safe.
my %chars_to_escape_when_quoting = (
    '"'  => '\\"',
    '\\' => '\\\\',
    '@'  => '\\@',

    # Escape single quotes because some parsers will strip leading/trailing
    # single quotes. NOTE: RFC 1035 does NOT describe this behavior!
    q{'} => q{\\'},

    # Escaped semicolons throw some buggy parsers off,
    # but Net::DNS::RR chokes on \DDD as the RFC defines it.
    # cf. RT #77444
    ';' => '\\;',

    # Case 86337: Escape newlines and carriage feeds.
    "\xa" => '\\010',
    "\xd" => '\\013',
);

my $_encode_keys_quoted = join( '|', map quotemeta, keys %chars_to_escape_when_quoting );

my $encode_regexp_x = q<(?x:
    \\\\                #backslash, then one of:
    (
        [^0-9]          #non-numeral
        |
        [01][0-9]{2}    #000 through 199
        |
        2[0-4][0-9]     #200 through 249
        |
        25[0-5]         #250 through 255
    )
)>;

sub encode_character_string {
    return q{""} if !length $_[0];

    # CPANEL-42688: Changed to quote every chunk of TXT record
    return q{"} . ( $_[0] =~ s{(${_encode_keys_quoted})}{$chars_to_escape_when_quoting{$1}}oegr ) . q{"};
}

#NB: RFC 1035 is unclear about how to decode something like "123";
#It has no spaces, so should we treat this as a literal string, or
#as quoted? And what of ""?
#The solution almost everything probably implements is to check whether
#the first character is a quote and, if so, assume the string should be
#parsed as quoted.
sub decode_character_string {

    my $str = ( $_[0] =~ m{$Cpanel::Regex::regex{'doublequotedstring'}}o ) ? $1 : $_[0];

    #We have to do all unescaping in sequence, which makes this regexp
    #a bit hairier than would be ideal.
    return (
        $str =~ s{$encode_regexp_x}{
        ($1 =~ tr{0-9}{}) ? chr $1 : $1
    }gexro
    );
}

# Cpanel::Net::DNS::ZoneFile::LDNS
# does not instantiate Net::DNS::RR for each record, unlike Net::DNS::ZoneFile::Fast
# in upstream CPAN. This means that records with RFC 1035 character-strings
# (TXT, SPF, and HINFO) need this extra step.
sub cp_zonefile_fast_post_process {
    my $list_ar = 'ARRAY' eq ref $_[0] ? $_[0] : \@_;

    for my $rec (@$list_ar) {
        if ( $rec->{'type'} eq 'TXT' || $rec->{'type'} eq 'SPF' ) {

            #NOTE: See commentary on encode_and_split_dns_txt_record_value();
            #this operation is essentially the reverse of that: taking multiple
            #character strings in a TXT/SPF and combining them into a single
            #string for whatever application sits atop this one.
            $rec->{'txtdata'}   = join( q<>, map { decode_character_string($_) } @{ $rec->{'char_str_list'} } );
            $rec->{'unencoded'} = 1;
        }
        elsif ( $rec->{'type'} eq 'HINFO' ) {
            for (qw(cpu os)) {
                $rec->{$_} = decode_character_string( $rec->{$_} );
            }
            $rec->{'unencoded'} = 1;
        }
    }

    return $list_ar;
}

#----------------------------------------------------------------------
# TXT records per se cannot contain a single string that is longer than
# 255 characters (cf. RFC 1035); however, they can contain *multiple* strings
# that can be up to that same length. It is therefore possible for
# applications to "encode" an overly long string by splitting it into
# multiple strings, then combining those into a single one when reading the
# TXT record; this achieves the same end as if TXT records could contain a
# single, arbitrarily long string.
#
# cf. RFC 1035
#
# This logic pertains to such applications as SPF and DKIM.
#
# Also, RFC 4408:
# 3.1.3 SPF or TXT records containing multiple strings are useful in
# constructing records that would exceed the 255-byte maximum length of
# a string within a single TXT or SPF RR record.
#
sub encode_and_split_dns_txt_record_value {
    my ($value) = @_;

    # handle some special cases
    return '""' if !length $value;

    return join( ' ', map { encode_character_string($_) } ( $value =~ /.{1,$MAX_TXT_LENGTH}/gso ) );
}

1;
