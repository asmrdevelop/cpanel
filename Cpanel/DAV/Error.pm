package Cpanel::DAV::Error;

# cpanel - Cpanel/DAV/Error.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings)

use Cpanel::Encoder::Tiny ();
use Cpanel::Version::Full ();
use Cpanel::Locale::Lazy 'lh';

sub format {
    my ($message) = @_;

    $message ||= lh()->maketext('Unknown Error');

    # Use Cpanel::Encoder::Tiny because Cpanel::Encoder::XML is unsuitable for XML special character encoding.
    my $encoded_message = Cpanel::Encoder::Tiny::safe_html_encode_str($message);
    my $encoded_version = Cpanel::Encoder::Tiny::safe_html_encode_str( Cpanel::Version::Full::getversion() );

    return <<EOF;
<?xml version="1.0" encoding="utf-8"?>
<d:error xmlns:d="DAV:" xmlns:cp="http://cpanel.net/ns">
  <cp:cpanel-version>$encoded_version</cp:cpanel-version>
  <cp:message>$encoded_message</cp:message>
</d:error>
EOF
}

1;
