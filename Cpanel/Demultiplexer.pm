package Cpanel::Demultiplexer;

# cpanel - Cpanel/Demultiplexer.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Carp           ();
use Cpanel::Logger ();

my $logger = Cpanel::Logger->new();

sub _default_exit {
    my $self = shift;
    exit @_;
}

sub exit {
    my $self = shift;
    if ( 'CODE' eq ref $self->{'exit'} ) {
        return $self->{'exit'}->(@_);
    }
    elsif ( exists $self->{'exit'} ) {
        $logger->warn('Supplied exit function is not code; using default.');
    }
    return $self->_default_exit(@_);
}

sub _default_die {
    my $self = shift;
    Carp::croak(@_);
}

sub die {
    my $self = shift;
    if ( 'CODE' eq ref $self->{'die'} ) {
        return $self->{'die'}->(@_);
    }
    elsif ( exists $self->{'die'} ) {
        $logger->warn('Supplied die function is not code; using default.');
    }
    return $self->_default_die(@_);
}

sub _default_warn {
    my $self = shift;
    Carp::carp(@_);
}

sub warn {
    my $self = shift;
    if ( 'CODE' eq ref $self->{'warn'} ) {
        return $self->{'warn'}->(@_);
    }
    elsif ( exists $self->{'warn'} ) {
        $logger->warn('Supplied warn function is not codes; using default.');
    }
    return $self->_default_warn(@_);
}

sub _default_out {
    my $self = shift;
    my $func = shift;
    if ( 'CODE' eq ref $func ) {
        return $func->(@_);
    }
    $logger->warn('Supplied function to out is not code; printing to stdout.');
    print @_;
}

sub out {
    my $self = shift;
    if ( 'CODE' eq ref $self->{'out'} ) {
        return $self->{'out'}->(@_);
    }
    elsif ( exists $self->{'out'} ) {
        $logger->warn('Supplied out function is not code; using default.');
    }
    return $self->_default_out(@_);
}

sub _default_print {
    my $self = shift;
    return print @_;
}

sub print {
    my $self = shift;
    if ( 'CODE' eq ref $self->{'print'} ) {
        return $self->{'print'}->(@_);
    }
    elsif ( exists $self->{'print'} ) {
        $logger->warn('Supplied print function is not code; using default.');
    }
    return $self->_default_print(@_);
}

sub register_callback {
    my ( $self, $name, $callback ) = @_;
    if ( 'CODE' ne ref $callback ) {
        $logger->warn('Attempted to register non code ref.');
        return;
    }
    $self->{$name} = $callback;
    return 1;
}

sub clear_callbacks {
    my $self = shift;
    foreach my $name ( keys %$self ) {
        delete $self->{$name};
    }
    return 1;
}

sub new {
    my $proto = shift;
    my $class = ref $proto || $proto;
    my $self  = {};
    bless $self, $class;
    return $self;
}

1;

__END__


=pod

=head1 NAME

Cpanel::Demultiplexer - a visitor of sorts

=head1 SYNOPSIS

    # instantiate and configure
    my $demux = Cpanel::Demultiplexer->new();
    $demux->register_callback( 'print', \&my_print_func );

    # use in called code
    $demux->print( 'This space for rent.' );
    $demux->out( \&some_printing_function, 'Your message here.' );
    $demux->warn( 'You sure?' );
    $demux->die( 'Oh noes.' );
    $demux->exit( $exit_code );


=head1 DESCRIPTION

For whatever reason, you don't want to fully refactor some code that performs direct output and behaves in otherwise unfriendly ways for usage in calling code that is not necessarily interested in the output.  Use a demultiplexer to preserve existing behavior for legacy callers and provide alternative behavior for callers who desire it.

=head2 RETURN VALUES

Each of the functionalities offered by the multiplexer will return the value of the underlying functionality.  So, by default...

    $demux->print( 'Some message.' );

    returns the same as...

    print 'Some message.';

This also holds true for custom functionality.

    # instantiate and cause printing to return 7
    my $demux = Cpanel::Demultiplexer->new();
    $demux->register_callback( 'print', sub { print @_; return 7; } );

=head2 HIJACKING OTHER OUTPUT FUNCTIONS

Sometimes, customized print-like functions are created that need to be intercepted.  The out method of the demultiplexer allows this.

    $demux->register_callback( 'out', \&func_to_store_output_somewhere );

    # in usage...
    $demux->out( \&some_outputting_func, 'Text for the output func.' );

=head1 CAVEATS

This class allows a user to provide ways to circumvent certain built in Perl mechanisms (exit/warn/die).  Use this power with care, as other parts of the code may make assumptions that those behaviors are honored.

Code that uses the demultiplexer should generally return after situations that would have default exit/die behaviors.

    die 'Oh noes.';

    becomes...

    $demux->die( 'Oh noes.' );
    return;


=cut
