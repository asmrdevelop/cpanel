package Cpanel::AdminBin::Script::Simple;

# cpanel - Cpanel/AdminBin/Script/Simple.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
#NOTE: Consider using Cpanel::AdminBin::Script::Call instead of this class.
#That module, in tandem with Cpanel::AdminBin::Call, offers a consistent,
#encapsulated means for userland code to communicate with admin logic,
#with exceptions and arbitrary inputs/outputs.
#----------------------------------------------------------------------

use strict;

use base qw(
  Cpanel::AdminBin::Script
);

#Overrides the base class's method of the same name.
sub _init_uid_action_arguments {
    my ($self) = @_;

    my $line1_ar = $self->_read_first_line();

    ( $self->{'caller'}{'_uid'}, $self->{'_action'} ) = splice( @$line1_ar, 0, 2 );
    $self->{'_arguments'} = $line1_ar;

    return;
}

1;
