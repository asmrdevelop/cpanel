package Install::BandwidthCache;

# cpanel - install/BandwidthCache.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use base qw( Cpanel::Task );

use strict;
use warnings;

use Cpanel::SafeRun::Simple ();

=head1 DESCRIPTION

    ReBuilding BandwidthDB RootCache
    by running scripts/build_bandwidthdb_root_cache_in_background

=over 1

=item Type: Sanity

=item Frequency: always

=item EOL: never

=back

=cut

our $VERSION = '1.1';

exit __PACKAGE__->runtask() unless caller;

sub new {
    my $proto = shift;
    my $self  = $proto->SUPER::new;

    $self->set_internal_name('bandwidth_cache');

    return $self;
}

sub perform {
    my $self = shift;

    my $cmd = '/usr/local/cpanel/scripts/build_bandwidthdb_root_cache_in_background';
    my $out = Cpanel::SafeRun::Simple::saferun($cmd);
    print $out if defined $out;

    return 1;
}

1;
