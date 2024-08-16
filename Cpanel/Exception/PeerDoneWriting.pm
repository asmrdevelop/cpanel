package Cpanel::Exception::PeerDoneWriting;

# cpanel - Cpanel/Exception/PeerDoneWriting.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::Exception::PeerDoneWriting

=head1 SYNOPSIS

    use Cpanel::Exception();

    die Cpanel::Exception::create_raw('PeerDoneWriting');

=head1 DESCRIPTION

This exception can be useful for handling the case where a C<sysread()> or
C<read()> has returned empty without error, which means we need to stop
reading from the associated filehandle. Instances of this class represent
the case of “I tried to read NN bytes as you asked, but the peer has stopped
sending (so you need to do something else).”

This class accepts no arguments; it is expected that each application will
create its own human-readable string to describe the condition.

B<You should always trap this exception.>

=head1 WHEN TO USE THIS CLASS

For cases where “I tried to read …” is an unexpected condition, e.g., clients,
it is probably reasonable to represent this condition with an exception
since those are cases where we expect our reads to succeed.

=head1 WHEN B<NOT> TO USE THIS CLASS

One case where we may not want to consider an empty read to be an error
is when we don’t know how much data is coming in. In this case an empty read
is the only way we know we’re done, so that’s probably best not considered
exceptional.

It’s probably something worth evaluating case by case.

=cut

use strict;
use warnings;

use parent qw( Cpanel::Exception );

1;
