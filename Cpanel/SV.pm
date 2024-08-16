package Cpanel::SV;

# cpanel - Cpanel/SV.pm                            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

# cPstrict is avoided here because it is indirectly loaded by perlinstaller.
# perlinstaller uses /usr/bin/perl.
use strict;
use warnings;

=head1 NAME

C<Cpanel::SV>

=head1 DESCRIPTION

C<Cpanel::SV> provides low level calls sometimes needed to interact with a variable.
Admittedly the only reason we have for this module is to manage taint issues at this
time but maybe we'll need it for something else in the future. *shrug*

=head1 FUNCTIONS

=head2 untaint

Previously, we did some acrobatic things to untaint variables. This has caused some
problems with newer perls. Instead, this interface will be used any time we want to
explicitly untaint something.

This code is designed to do nothing unless the global ${^TAINT} is set.

Please only pass 1 variable at a time.

Returns: The same variable passed in to ease coding.

=cut

sub untaint {
    return $_[0] unless ${^TAINT};
    require    # Cpanel::Static OK - we should not untaint variables as part of updatenow.static
      Taint::Util;
    Taint::Util::untaint( $_[0] );
    return $_[0];
}

1;
