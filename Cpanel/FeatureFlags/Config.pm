# cpanel - Cpanel/FeatureFlags/Config.pm           Copyright 2023 cPanel, L.L.C.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::FeatureFlags::Config;

use strict;
use warnings;

use v5.20;
use experimental qw(signatures try);
use cpcore;

our $VERSION = '1.0.0';

use Cpanel::FeatureFlags::Constants ();    ## PPI USE OK -- Needed in constants below
use Cpanel::Slurper                 ();

use constant ADD_FLAGS_PATH    => Cpanel::FeatureFlags::Constants::CONFIG_DIR() . '/add.cfg';
use constant REMOVE_FLAGS_PATH => Cpanel::FeatureFlags::Constants::CONFIG_DIR() . '/remove.cfg';

=head1 MODULE

C<Cpanel::FeatureFlags::Config>

=head1 DESCRIPTION

C<Cpanel::FeatureFlags::Config> provides tooling to read in the add.cfg and remove.cfg files.
These files contain a list of feature flags to enabled and disable on the server. Each feature
flag cooresponds to one piece of optional product functionality.

=head1 SYNOPSIS

  use Cpanel::FeatureFlags::Config ();

=head1 FUNCTIONS

=head2 get_added_flags()

Get the list of flags to enable on the server.

=head3 RETURNS

C<ARRAY String> - list of flags to add. Each flag cooresponds to one feature flag

=cut

sub get_added_flags() {
    return _read(ADD_FLAGS_PATH);
}

=head2 get_removed_flags()

Get the list of flags to disable on the server.

=head3 RETURNS

C<ARRAY String> - list of flags to remove. Each flag cooresponds to one feature flag

=cut

sub get_removed_flags() {
    return _read(REMOVE_FLAGS_PATH);
}

=head2 _read($PATH)

Read in the list of flags from the .cfg file located on C<$PATH>.

=head3 ARGUMENTS

=over

=item $PATH - C<String>

The path to the .cfg file.

=back

=head3 RETURNS

C<ARRAY String> - list of flags to add. Each flag cooresponds to one feature flag

=cut

sub _read ($path) {
    my @list;
    try {
        if ( my $text = Cpanel::Slurper::read($path) ) {
            @list = split( /\n/, $text );
        }
    }
    catch ($e) {
        if ( $e && !$e->isa('Cpanel::Exception::IO::FileNotFound') ) {
            throw $e;
        }
    };

    return \@list;
}

1;
