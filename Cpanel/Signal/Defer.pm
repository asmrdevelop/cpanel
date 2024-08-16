package Cpanel::Signal::Defer;

# cpanel - Cpanel/Signal/Defer.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

my $logger;

#Entries in an instance's _deferred list must be numbers because of Perl 5.6.
#Lacking the OS's signal numbers, we create our own signal numbers here.
my %OUR_SIGNAL_NUMBER;
my $MAX_OUR_SIGNAL_NUMBER = 10;

#These are what we usually want to trap.
sub NORMALLY_DEFERRED_SIGNALS {
    return [qw(TERM PIPE HUP INT USR1 USR2 ALRM ABRT)];
}

sub new {
    my ( $class, %opts ) = @_;

    my $self = {};
    bless $self, $class;

    $self->reset_deferred();

    if ( %opts && $opts{'defer'} ) {
        $self->defer( %{ $opts{'defer'} } );
    }

    return $self;
}

sub defer {
    my ( $self, %opts ) = @_;
    my $context = $opts{'context'} || caller(1);

    # Deferring a signal twice will destory the original handler
    my %signals = map { $_ => undef } @{ $opts{'signals'} };

    for my $signal ( sort keys %signals ) {
        my $sig_copy = $SIG{$signal};

        if ( $sig_copy && $sig_copy eq 'IGNORE' ) {

            # Whostmgr::Accounts::Create sets these to ignore, so no point in warning about them
            #            $logger ||= Cpanel::Logger->new();
            #            $logger->warn("Cannot defer signal $signal as it is already set to IGNORE");
            next;
        }

        if ( !$OUR_SIGNAL_NUMBER{$signal} ) {
            $OUR_SIGNAL_NUMBER{$signal} = $MAX_OUR_SIGNAL_NUMBER;
            $MAX_OUR_SIGNAL_NUMBER++;
        }

        my $warning = q{Deferring signal '} . $signal . q{' from context '} . $context . q{'};

        if ( $self->{'_original_signal_handlers'}{$signal} ) {
            require Cpanel::Carp;
            die Cpanel::Carp::safe_longmess("“$signal” cannot be defered twice.");
        }

        $self->{'_original_signal_handlers'}{$signal} = $sig_copy || "DEFAULT";

        $SIG{$signal} = sub {    ## no critic qw(Variables::RequireLocalizedPunctuationVars)
            warn $warning;
            $self->{'_last_deferral_list_index'}++;
            $self->{'_deferred'}[ $self->{'_last_deferral_list_index'} ] = $OUR_SIGNAL_NUMBER{$signal};

            return;
        };
    }

    return;
}

sub get_deferred {
    my ($self) = @_;

    my %number_signal = reverse %OUR_SIGNAL_NUMBER;

    return [ map { $_ ? $number_signal{$_} : () } @{ $self->{'_deferred'} } ];
}

sub reset_deferred {
    my ($self) = @_;

    $self->{'_deferred'}                 = [];
    $self->{'_last_deferral_list_index'} = -1;

    return;
}

sub restore_original_signal_handlers {
    my ($self) = @_;

    foreach my $signal ( keys %{ $self->{'_original_signal_handlers'} } ) {
        $SIG{$signal} = delete $self->{'_original_signal_handlers'}{$signal};
    }

    return;
}

sub DESTROY {
    my $self = shift or return;

    return 1 if !scalar keys %{ $self->{'_original_signal_handlers'} };

    return $self->restore_original_signal_handlers();
}

1;

__END__

=encoding utf-8

=head1 NAME

Cpanel::Signal::Defer - Streamlined signal deferral

=head1 DESCRIPTION

This module is useful for ensuring that a block of code will ignore
whichever signals it should, which can help to ensure that a set of
operations is atomic.

=head1 SYNOPSIS

    use Cpanel::Signal::Defer ();

    my $deferred_signals_ar;
    {
        my @to_trap = qw(TERM PIPE HUP INT USR1 USR2 ALRM);
        my $defer = Cpanel::Signal::Defer->new(
            defer => {
                signals => \@to_trap,
                context => 'update to webserver configuration',
            }
        );

        #...Set of operations that should be atomic.

        $deferred_signals_ar = $defer->get_deferrals();

        $defer->restore_original_signal_handlers(); # will be done by DESTROY if not called
    }

    if ( $deferred_signals_ar && @$deferred_signals_ar ) {
        warn "The following signals have been received and ignored: @$deferred_signals_ar\n";
    }
