package Cpanel::DnsUtils::ResolverSingleton;

# cpanel - Cpanel/DnsUtils/ResolverSingleton.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::DNS::Unbound ();

# Exposed for testing
our $_RESOLVER;

# Avoid DESTROY at global destruction time:
END { undef $_RESOLVER }

=encoding utf-8

=head1 NAME

Cpanel::DnsUtils::ResolverSingleton

=head1 SYNOPSIS

    use Cpanel::DnsUtils::ResolverSingleton ();

    my $resolver = Cpanel::DnsUtils::ResolverSingleton::singleton();

=head1 DESCRIPTION

This module stores a single no options instance of a C<Cpanel::DNS::Unbound> so it can be shared across different modules.

=head1 FUNCTIONS

=head2 singleton()

Gets the singleton object, creating it if it's not already created.

=over 2

=item Input

None

=item Output

=over 3

=item C<SCALAR>

Returns the singleton object.

=back

=back

=cut

sub singleton {
    return $_RESOLVER ||= Cpanel::DNS::Unbound->new( timeout => 4 );
}

1;
