package Cpanel::SpamAssassin::Constants;

# cpanel - Cpanel/SpamAssassin/Constants.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8
=head1 NAME

Cpanel::SpamAssassin::Constants

=head1 SYNOPSIS

    my $v = Cpanel::SpamAssassin::Constants::DEFAULT_REQUIRED_SCORE();

=head1 FUNCTIONS

=head2 DEFAULT_REQUIRED_SCORE

Returns SpamAssassin’s default C<required_score> value; i.e., the
minimum spam score at which SpamAssassin will consider a piece of mail
to be spam.

=cut

#NB: This is a pretty aggressive score that will filter a lot of mail.
use constant DEFAULT_REQUIRED_SCORE => 5;

# https://metacpan.org/source/KMCGRAIL/Mail-SpamAssassin-3.4.1/spamc/spamc.pod
use constant EX_UNAVAILABLE => 69;

1;
