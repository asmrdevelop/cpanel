# cpanel - Cpanel/StatsManager/Consts.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::StatsManager::Consts;

use strict;
use warnings;

=head1 MODULE

C<Cpanel::StatsManager::Consts>

=head1 DESCRIPTION

C<Cpanel::StatsManager::Consts> provides a common place to put some of
the reusable constants use by the web log analyzer configuration system.

=head1 SYNOPSIS

  use Cpanel::StatsManager::Consts ();
  foreach my $logger (@Cpanel::StatsManager::Consts::ALL_ANALYZERS) {
    print "$logger\n";
  }

=cut

our @ALL_ANALYZERS = qw(
  analog
  awstats
  webalizer
);

1;
