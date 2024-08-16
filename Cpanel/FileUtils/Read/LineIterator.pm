package Cpanel::FileUtils::Read::LineIterator;

# cpanel - Cpanel/FileUtils/Read/LineIterator.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
#NOTE: There's probably no gain from using this module directly; it
#basically exists as a "helper" class to Cpanel::FileUtils::Read.
#----------------------------------------------------------------------

use strict;

use Try::Tiny;

use base qw(
  Cpanel::FileUtils::Read::IteratorBase
);

sub _run {
    my ($self) = @_;

    my $fh = $self->{'_fh'};

    $self->{'_bytes_read_at_start'} = tell $fh;

    my $todo_cr         = $self->{'_todo_cr'};
    my $iteration_index = 0;

    $self->{'_iteration_index_sr'} = \$iteration_index;

    return $self->_run_try_catch(
        sub {
            while ( readline $fh ) {
                local $!;
                $todo_cr->($self);
                $iteration_index++;
            }
        }
    );
}

sub get_bytes_read {
    my ($self) = @_;

    return ( tell $self->{'_fh'} ) - $self->{'_bytes_read_at_start'};
}

sub _READ_ERROR_EXCEPTION_CLASS {
    return 'IO::FileReadError';
}

package Cpanel::FileUtils::Read::LineIterator::_STOP;

sub new {
    my ($class) = @_;

    my $scalar;
    my $self = \$scalar;
    return bless $self, $class;
}

1;
