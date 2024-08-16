package Cpanel::SSL::DefaultKey;

# cpanel - Cpanel/SSL/DefaultKey.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::SSL::DefaultKey

=head1 SYNOPSIS

    if ( !Cpanel::SSL::DefaultKey::is_valid_value($specimen) ) {
        die "bad: $specimen";
    }

=head1 DESCRIPTION

Convenience logic for SSL/TLS default-key settings.

=cut

#----------------------------------------------------------------------

use Cpanel::SSL::DefaultKey::Constants ();    # PPI NO PARSE - mis-parse

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $yn = is_valid_value( $SPECIMEN )

Returns a boolean that indicates whether $SPECIMEN is a valid value for the
system-wide TLS default key setting.

=cut

sub is_valid_value ($value) {
    return 0 + grep { $_ eq $value } Cpanel::SSL::DefaultKey::Constants::OPTIONS;
}

1;
