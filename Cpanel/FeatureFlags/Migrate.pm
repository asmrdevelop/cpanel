# cpanel - Cpanel/FeatureFlags/Migrate.pm          Copyright 2023 cPanel, L.L.C.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::FeatureFlags::Migrate;

use strict;
use warnings;

use v5.20;
use experimental qw(signatures);

use Cpanel::Autodie                 ();
use Cpanel::FeatureFlags::Constants ();

my $source      = Cpanel::FeatureFlags::Constants::LEGACY_STORAGE_DIR();
my $destination = Cpanel::FeatureFlags::Constants::STORAGE_DIR();

=head1 MODULE

C<Cpanel::FeatureFlags::Migrate>

=head1 DESCRIPTION

C<Cpanel::FeatureFlags::Migrate> provides tools to help migrate from
the experimental system.

=head1 SYNOPSIS

  use Cpanel::FeatureFlags::Migrate ();
  Cpanel::FeatureFlags::Migrate::migrate_experimental_system();

=head1 FUNCTIONS

=head2 migrate_experimental_system()

Migrate the earlier experimental feature flag directory into the new
directory used by the general feature flag system and remove the
legacy directory.

=cut

sub migrate_experimental_system() {

    use Cpanel::Autodie;
    Cpanel::Autodie::mkdir_if_not_exists( $destination, Cpanel::FeatureFlags::Constants::STORAGE_DIR_PERMS() );

    _move_flags( $source, $destination );

    Cpanel::Autodie::rmdir_if_exists($source);

    return 1;
}

=head1 PRIVATE FUNCTIONS

=head2 _ENOENT()

Returns error used when file or directory does not exist.

=cut

sub _ENOENT { return 2; }

=head2 _move_flags($source, $destination)

Moves the flags from the C<$source> directory to the C<$detination> directory.

=cut

sub _move_flags ( $source, $destination ) {
    opendir( my $dh, $source ) or do {
        die $! if $! != _ENOENT();
        return;
    };

    while ( my $file = readdir $dh ) {
        next if $file =~ m/^[.]+$/;
        Cpanel::Autodie::rename( "$source/$file", "$destination/$file" );
    }
    closedir $dh;
    return 1;
}

1;
