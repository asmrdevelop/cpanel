package Cpanel::Encoder::CSV;

# cpanel - Cpanel/Encoder/CSV.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

# passes, but not for production
#use strict;

our %CSV_ESCAPE_MAP = (
    "\n" => "\\n",
    "\r" => "\\r",
    "\\" => "\\\\",
    '"'  => '""',
);

sub safe_csv_encode_str {
    my $text = shift;
    $text =~ s/([\\"\n\r])/$CSV_ESCAPE_MAP{$1}/g;

    if ( $text =~ /,/ ) {
        $text = qq{"$text"};
    }

    return $text;
}

1;
