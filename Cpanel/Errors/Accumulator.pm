package Cpanel::Errors::Accumulator;

# cpanel - Cpanel/Errors/Accumulator.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

sub new {
    my $class = shift;
    my (%OPTS) = @_;

    my $self = {};
    $self->{'failure_count'} = 0;
    $self->{'failures'}      = [];
    $self->{'max_failures'}  = $OPTS{'max_failures'};
    $self->{'fatal_regex'}   = $OPTS{'fatal_regex'};

    bless $self, $class;

    return $self;
}

sub get_fatal_failure_reason {
    my ($self) = @_;
    return $self->{'fatal_failure_reason'} || 'unknown';
}

sub get_failures_as_string {
    my ($self) = @_;
    return join( "\n", @{ $self->{'failures'} } );
}

sub get_failures {
    my ($self) = @_;
    return $self->{'failures'};
}

sub get_failure_count {
    my ($self) = @_;
    return $self->{'failure_count'};
}

sub accumulate_failure_is_fatal {
    my ( $self, $failure, $failure_reason ) = @_;

    $self->{'failure_count'}++;

    push @{ $self->{'failures'} }, "ERROR " . int($!) . ": $!: $failure: $failure_reason";

    if ( $self->{'fatal_regex'} && $! =~ $self->{'fatal_regex'} ) {
        $self->{'fatal_failure_reason'} = scalar $!;
        return 1;
    }
    elsif ( $self->{'max_failures'} && $self->{'failure_count'} >= $self->{'max_failures'} ) {
        $self->{'fatal_failure_reason'} = "Reached maximum failures: $self->{'max_failures'}";
        return 1;
    }

    return 0;
}

1;
