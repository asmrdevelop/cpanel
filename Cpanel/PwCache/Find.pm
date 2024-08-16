package Cpanel::PwCache::Find;

# cpanel - Cpanel/PwCache/Find.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic (RequireUseWarnings)

use Cpanel::LoadFile::ReadFast ();

our $PW_CHUNK_SIZE = 1 << 17;

sub field_with_value_in_pw_file {
    my ( $passwd_fh, $field, $value, $lc_flag ) = @_;

    return if ( $value =~ tr{\x{00}-\x{1f}\x{7f}:}{} );

    my $needle = $field == 0 ? "\n${value}:" : ":${value}";
    my $haystack;

    my $match_pos = 0;
    my $line_start;
    my $line_end;
    my $not_eof;
    my $data = "\n";

    # This loop continues one iteration past the EOF to match any data in the buffer that is not terminated with a newline.
    while ( ( $not_eof = Cpanel::LoadFile::ReadFast::read_fast( $passwd_fh, $data, $PW_CHUNK_SIZE, length $data ) ) || length($data) > 1 ) {

        # Grab a search haystack that ends on a newline or EOF
        # If this isn't EOF, the buffer will be truncated to contain only the remaining bytes
        # If $lc_flag is provided and == 1, the $haystack and $needle will be lower-cased to perform a 'normalized' lookup
        $haystack = $not_eof ? substr( $data, 0, rindex( $data, "\n" ), '' ) : $data;

        if ( $lc_flag && $lc_flag == 1 ) {
            $haystack = lc $haystack;
            $needle   = lc $needle;
        }

        # Iterate through matches of the needle...
        # This while conditional is the only part of the logic that matches the search string.
        while ( -1 < ( $match_pos = index( $haystack, $needle, $match_pos ) ) ) {

            # Assertions about characters preceeding the match go before assertions about
            # characters following the match since the preceeding characters are likely to
            # be in the L1/L2 cache already.
            #
            # Look backwards for the newline before this line to find its starting point
            $line_start = ( !$field ? $match_pos : rindex( $haystack, "\n", $match_pos ) ) + 1;
            if (
                # field 0 matches can be identified by the index() alone
                !$field || (

                    # field 1+ matches are identified by counting the number of preceeding ':' characters
                    $field == ( substr( $haystack, $line_start, $match_pos - $line_start + 1 ) =~ tr{:}{} )

                    # and field 1+ matches need to be followed by the end of the haystack or a field/line separator
                    && ( length($haystack) == $match_pos + length($needle) || substr( $haystack, $match_pos + length($needle), 1 ) =~ tr{:\n}{} )
                )
            ) {
                # the start of the line is already saved, find the end of the line and grab it
                $line_end = index( $haystack, "\n", $match_pos + length($needle) );
                my $line = substr( $haystack, $line_start, ( $line_end > -1 ? $line_end : length($haystack) ) - $line_start );

                return split( ':', $line );
            }
            $match_pos += length($needle);
        }
        last unless $not_eof;
    }
    return;
}

1;
