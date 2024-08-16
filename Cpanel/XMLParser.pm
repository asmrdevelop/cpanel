package Cpanel::XMLParser;

# cpanel - Cpanel/XMLParser.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use XML::Simple ();

$XML::Simple::PREFERRED_PARSER = "XML::SAX::PurePerl";

our $VERSION = '1.1';

*XMLin = \&XML::Simple::XMLin;

1;
