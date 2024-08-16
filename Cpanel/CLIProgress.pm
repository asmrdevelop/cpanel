
# cpanel - Cpanel/CLIProgress.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::CLIProgress;

use strict;

use IO::Interactive::Tiny ();
use Cpanel::Locale 'lh';

sub new {
    my ( $package, @args ) = @_;
    my $self = {@args};

    $self->{interactive} = IO::Interactive::Tiny::is_interactive();
    $self->{width} ||= 50;

    bless $self, $package;
    return $self;
}

# Allow deferring initialization until the function that actually uses the progress bar is run
sub init {
    my ( $self, @args ) = @_;
    %$self = ( %$self, @args );
    return 1;
}

sub increment {
    my ($self) = @_;
    $self->_must_be_initted;

    ++$self->{pos};

    return $self;
}

sub draw {
    my ($self) = @_;
    $self->_must_be_initted;
    return if !$self->{interactive};

    my $fraction       = $self->{pos} / $self->{max};
    my $progress_width = int( $self->{width} * $fraction );

    # Serves two purposes:
    #   1. If the rounding error causes the final mark to fall short of the end of the bar, force it to the end.
    #   2. If progress unexpectedly continues beyond max, just stay stuck at max.
    $progress_width = $self->{width} if $self->{pos} >= $self->{max};

    my $progress  = ' ' x $progress_width;
    my $remaining = '.' x ( $self->{width} - $progress_width );

    local $| = 1;

    print "\r\033[7m$progress\033[m$remaining\033[m ($self->{pos} / $self->{max})";

    return $self;
}

sub done {
    my ($self) = @_;
    $self->_must_be_initted;
    return if !$self->{interactive};
    print "\n";
    return $self;
}

sub _must_be_initted {
    my ($self) = @_;
    if ( !defined( $self->{pos} ) || !defined( $self->{max} ) ) {
        die lh()->maketext('You must initialize the progress bar before using it.');
    }
    return 1;
}

sub max {
    my ( $self, $set ) = @_;
    if ( defined $set ) {
        $self->{max} = $set;
    }
    return $self->{max};
}

1;
