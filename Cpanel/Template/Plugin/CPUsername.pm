package Cpanel::Template::Plugin::CPUsername;

# cpanel - Cpanel/Template/Plugin/CPUsername.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
#NOTE: This is a base class, but it can be instantiated as well.
#----------------------------------------------------------------------

use strict;

use base 'Template::Plugin';

use Cpanel::Validate::Username ();

sub get_reserved_usernames {
    return [ Cpanel::Validate::Username::list_reserved_usernames() ];
}

sub get_reserved_username_patterns {
    return [ Cpanel::Validate::Username::list_reserved_username_patterns() ];
}

sub make_strict_regexp_str {
    my ( $self, $for_transfer ) = @_;
    return Cpanel::Validate::Username::make_strict_regexp_str($for_transfer);
}

sub get_max_username_length {
    return $Cpanel::Validate::Username::MAX_LENGTH;
}

1;
