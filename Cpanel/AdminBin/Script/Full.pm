package Cpanel::AdminBin::Script::Full;

# cpanel - Cpanel/AdminBin/Script/Full.pm          Copyright 2022 cPanel, L.L.C.
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

use Cpanel::AdminBin::Serializer ();

use base qw(
  Cpanel::AdminBin::Script
);

#Overrides the base class's method of the same name.
sub _init_uid_action_arguments {
    my ($self) = @_;

    my $line1_ar = $self->_read_first_line();
    my $action   = shift @$line1_ar;

    $self->{'caller'}{'_uid'} = $ARGV[0];

    @{$self}{qw( _action  _arguments )} = (
        $action,
        $line1_ar,
    );

    $self->_read_extended_arguments();

    return;
}

#NOTE: This assumes that _init_uid_action_arguments has already been run!
sub _read_extended_arguments {
    my ($self) = @_;

    my $input;

    my $stdin = \*STDIN;
    my $check = readline($stdin);
    chomp($check) if $check;

    if ( length $check ) {
        if ( $check ne '.' ) {
            $self->die("Malformed extended input (must begin with “.” on its own line).");
        }

        eval {
            $input = Cpanel::AdminBin::Serializer::SafeLoadFile($stdin);
            1;
        } or $self->die($@);
    }

    return $self->{'_extended_args'} = $input;
}

sub get_extended_arguments {
    my ($self) = @_;

    return $self->{'_extended_args'};
}

1;
