package Cpanel::Template::Plugin::EximLocalOpts;

# cpanel - Cpanel/Template/Plugin/EximLocalOpts.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent 'Template::Plugin';

=encoding utf-8

=head1 NAME

Cpanel::Template::Plugin::EximLocalOpts - Template Toolkit plugin for accessing Exim config items

=head1 SYNOPSIS

    [%
        use EximLocalOpts;
        SET is_using_smart_host = EximLocalOpts.is_using_smart_host();
    %]

=head1 DESCRIPTION

This module provides a Template Toolkit plugin for accessing configuration settings
in the Exim configuration.

=head1 FUNCTIONS

==head2 is_using_smart_host

Determines if Exim is configured to use external smart host routes

=over 2

=item Input

=over 3

None

=back

=item Output

=over 3

=item C<SCALAR>

Returns truthy if Exim is configured to use a smart host, falsy if not

=back

=back

=cut

sub is_using_smart_host {
    require Cpanel::Exim::Config::LocalOpts;
    return Cpanel::Exim::Config::LocalOpts::is_using_smart_host();
}

1;
