package Cpanel::Update::Blocker;

# cpanel - Cpanel/Update/Blocker.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Update::Blocker::Base   ();    # PPI USE OK - Used for inheritance of common blocker logic.
use Cpanel::Update::Blocker::Always ();    # PPI USE OK - Used for inheritance of blocker checks that always happen.
use Cpanel::Update::Blocker::LTS    ();    # PPI USE OK - Used for inheritance of common blocker logic.

use parent -norequire, qw{ Cpanel::Update::Blocker::Base Cpanel::Update::Blocker::Always Cpanel::Update::Blocker::LTS };

=head1 NAME

Cpanel::Update::Blocker - Determines if upgrades are blocked. Is only required to be aware of blockers up to and including the next LTS version.

=head1 USAGE

    my $blocker = Cpanel::Update::Blocker->new({logger => $logger, # Optional
                                                starting_version => '11.70.0.1',
                                                target_version => '11.78.0.5',
                                                upconf_ref => $self->{'upconf_ref'},
                                              });

    # Check if this object will allow a upgrade from a previous version
    $blocker->is_upgrade_blocked();

=head1 DESCRIPTION

Designed exclusively for Cpanel::Update::Now->can_update();

=head1 Blocker Roles

Because of the growing complexity of this module, the module has had its common code moved out into Role modules.

::Base includes all the common logic surrounding the class, like notification and upgrade delays.

::Always includes all the checks that do not have an expiration date.

::LTS includes checks that are there to block someone from going to the next major LTS and then should go away.

All are parent classes so can be invoked as a method call.

=head1 Adding a Blocker

If you want to add a blocker, you need to know if the blocker is for the current LTS cycle or if it is a blocker check that needs to happen always for now on.

Blocker checks happen every version change. Your code will need to be aware of this.

=head1 METHODS

=over

=item B<is_upgrade_blocked>

Any time there is a version change, we call this subroutine. Your temporary checks (will eventually be removed) go here.

=back

=cut

# DO NOT MODIFY THIS subroutine. Please add to perform_lts_specific_checks or perform_global_checks instead.

sub is_upgrade_blocked {
    my ($self) = @_;
    ref $self eq __PACKAGE__ or die('This is a method call.');

    # Global checks are performed for all version changes.
    # Lives in Cpanel::Update::Blocker::Always
    my $keep_checking = $self->perform_global_checks();

    if ($keep_checking) {

        # Lives in Cpanel::Update::Blocker::LTS
        $self->perform_lts_specific_checks() unless $ENV{CPANEL_BASE_INSTALL};

        # Delaying upgrade; force is only used here to bypass delayed upgrade. All other blockers will be asserted.
        # If we have any blockers that were auto-resolved, and the upgrade was delayed (return code: 8), then
        # we block the upgrade, but do not notify the admin about the upgrade being 'delayed'.
        if ( $self->delay_upgrade() == 8 ) {
            $self->generate_blocker_file(0);
            return $self->is_fatal_block() + 1;
        }
    }

    # Create a blocker if @messages or cleanup the old blocker file since there is no block now.
    $self->generate_blocker_file(1);

    ## false return means 'upgrade is not blocked', but might have produced a warning
    return $self->is_fatal_block();
}

1;
