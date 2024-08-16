package Cpanel::ExitValues;

# cpanel - Cpanel/ExitValues.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# A base class.
#----------------------------------------------------------------------

use strict;

#referenced from tests
our $_UNKNOWN_KEY = 'UNKNOWN EXIT VALUE';

#e.g., Cpanel::ExitValues::rsync->number_to_string(6)
#
sub number_to_string {
    my ( $class, $number ) = @_;

    return { $class->_numbers_to_strings() }->{$number} || "$_UNKNOWN_KEY ($number)";
}

sub error_is_nonfatal_for_cpanel {
    my ( $class, $number ) = @_;

    return ( grep { $_ == $number } $class->_CPANEL_NONFATAL_ERROR_CODES() ) ? 1 : 0;
}

#Override this method in subclasses.
sub _numbers_to_strings { die 'ABSTRACT' }

#Override this method in subclasses, if needed.
sub _CPANEL_NONFATAL_ERROR_CODES { }

1;
