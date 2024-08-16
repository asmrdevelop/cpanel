package Cpanel::PwUtils::Lookup;

# cpanel - Cpanel/PwUtils/Lookup.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::StringFunc::LineIterator ();

# Arguments:
#
#   $passwd_sr - A scalar reference pointing to the contents of the passwd or
#                shadow file.
#  $matcher_cr - A code ref which accepts an array ref representing the fields
#                on one line of the file. Should return true to trigger a match
#                and false to keep looking.
sub lookup_entry_from_pw_text {
    my ( $passwd_sr, $matcher_cr ) = @_;
    my $result;
    Cpanel::StringFunc::LineIterator->new(
        $$passwd_sr,
        sub {
            my ( $iterator, $line ) = ( shift, $_ );
            my @fields = split /:/, $line;
            if ( $matcher_cr->( \@fields ) ) {
                $result = \@fields;
                $iterator->stop;
            }
        }
    );
    return $result;
}

1;
