package Cpanel::Email::Normalize::EmailLocalPart;

# cpanel - Cpanel/Email/Normalize/EmailLocalPart.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::StringFunc::Case ();
use Cpanel::StringFunc::Trim ();

sub normalize {
    my ($name) = @_;
    return unless defined $name;
    $name =~ tr{\0}{}d;
    Cpanel::StringFunc::Trim::ws_trim( \$name );
    return Cpanel::StringFunc::Case::ToLower($name);    # To match usage in addpop
}

sub scrub {
    my ($name) = @_;
    return unless defined $name;
    $name = normalize($name);
    $name =~ tr/^a-zA-Z0-9!#\$\-=?^_{}~.//cd;
    $name =~ s/\.\.+/./g;
    return if 0 == length $name;
    return $name;
}

1;
