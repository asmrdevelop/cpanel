# cpanel - Cpanel/FeatureFlags/Constants.pm        Copyright 2023 cPanel, L.L.C.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::FeatureFlags::Constants;

use strict;
use warnings;
use cpcore;

our $VERSION = '1.0.0';

=head1 MODULE

C<Cpanel::FeatureFlags::Constant>

=head1 DESCRIPTION

File where feature flag constants are kept. Do not add any non-constants here.

=head1 CONSTANTS

=head2 CONFIG_DIR - string

The private directory where the applications add.cfg and remove.cfg feature flags
files are published.

=cut

use constant CONFIG_DIR => '/usr/local/cpanel/feature-flags';

=head2 CONFIG_DIR_PERMS - number

Permissions to limit the configuration directory to owner only (root)

=cut

use constant CONFIG_DIR_PERMS => 0700;

=head2 STORAGE_DIR - string

The private directory where cpanel stores active feature flags.

=cut

use constant STORAGE_DIR => '/var/cpanel/feature-flags';

=head2 STORAGE_DIR_PERMS - number

Permissions to limit the storage directory to owner only (root) changing,
but everyone else can read the flags.

=cut

use constant STORAGE_DIR_PERMS => 0755;

=head2 LEGACY_STORAGE_DIR - string

The private directory where cpanel previously stored experimental feature flags.

=cut

use constant LEGACY_STORAGE_DIR => '/var/cpanel/experimental';

1;
