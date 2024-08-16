package Cpanel::Task::Main;
use base qw( Cpanel::Task );

use strict;

our $VERSION = '1.0';

sub new {
    my $proto = shift;
    my $self  = $proto->SUPER::new;

    $self->{'display-name'}  = 'main';
    $self->{'internal-name'} = 'main';
    $self->{'summary'}       = 'Main-run task dependency';
    $self->{'dependencies'}  = [];

    return $self;
}

sub create_history_msg {
    my $self = shift;
    return;
}

1;

__END__
