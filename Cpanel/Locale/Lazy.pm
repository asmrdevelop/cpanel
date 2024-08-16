
# cpanel - Cpanel/Locale/Lazy.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Locale::Lazy;

use strict;

=head1 NAME

Cpanel::Locale::Lazy

=head1 SYNOPSIS

  use Cpanel::Locale::Lazy 'lh';
  ...
  warn lh()->maketext('Something bad happened.');

=head1 DESCRIPTION

This module provides ready access to a locale handle (via Cpanel::Locale) while
deferring the loading of dependencies until requested at run time. This allows
you to keep the extra memory usage of modules like CDB_File out of daemon processes
that fork off children for their actual work.

=head1 FUNCTIONS

=head2 lh()

Loads Cpanel::Locale if not already loaded and returns a locale handle.

The lh() function is exportable from Cpanel::Locale::Lazy, just as it is from
Cpanel::Locale.

=cut

sub lh {
    require Cpanel::Locale;
    {
        BEGIN { ${^WARNING_BITS} = ''; }
        *lh = \&Cpanel::Locale::lh;
    }
    return Cpanel::Locale::lh();
}

# Allow exporting lh() without using Exporter.pm
sub import {
    my ( $package, @args ) = @_;
    my ($namespace) = caller;
    if ( @args == 1 && $args[0] eq 'lh' ) {
        no strict 'refs';    ## no critic(ProhibitNoStrict)
        my $exported_name = "${namespace}::lh";
        *$exported_name = \*lh;
    }
    return;
}

=head1 SEE ALSO

Cpanel::Locale - This module also has an exportable lh() function which provides lazy instantiation
but lacks the lazy loading of dependencies.

=cut

1;
