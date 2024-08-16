package Cpanel::Task::Base;
use base qw( Cpanel::Task );

use strict;

our $VERSION = '1.0';

sub new {
    my $proto = shift;
    my $self  = $proto->SUPER::new;

    $self->set_internal_name('base');
    $self->set_summary('Base system.');

    return $self;
}

1;

__END__
