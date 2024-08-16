package Cpanel::Update::Blocker::LTS;

# cpanel - Cpanel/Update/Blocker/LTS.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Update::Blocker::Base ();    # PPI USE OK - Used for inheritance of common blocker logic.

# Needed for testing of these subs.
use parent -norequire, qw{ Cpanel::Update::Blocker::Base };

use Try::Tiny;

=head1 NAME

Cpanel::Update::Blocker::LTS - Provides the code which is run to block a specific LTS upgrade and then goes away.

=head1 DESCRIPTION

This is a parent class of Cpanel::Update::Blocker. It provides the following methods for the child class:

perform_lts_specific_checks

=head1 METHODS

=head2 B<new>

As this is a Role type class, this class is not designed to be instantiated directly.

=cut

sub new {
    die("Try Cpanel::Update::Blocker->new");
}

=head2 <perform_lts_specific_checks>

Any time there is a version change, we call this subroutine. Your temporary checks (will eventually be removed) go here.

If your blocker is for the current LTS cycle, then please put it here.

Create a sub, adding comments explaining its purpose and when it can be removed.
The sub should be called from perform_lts_specific_checks. Please also add intent comments on that line too.

=cut

# DO NOT do requires in this subroutine. By doing so, you're not assuring that the module is shipped
# with updatenow.static.

sub perform_lts_specific_checks {
    my ($self) = @_;
    ref $self eq 'Cpanel::Update::Blocker' or die('This is a method call for Cpanel::Update::Blocker');

    # If you want to do an upgrade blocker that eventually goes away, you're in the right place!
    # No LTS specific checks exists, but we ask that you review what was done in 97e299da66 as
    # an example of how you might build one here.

    return;
}

1;
