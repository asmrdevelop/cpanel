package Cpanel::LoggerAdapter::Lazy;

# cpanel - Cpanel/LoggerAdapter/Lazy.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::LoggerAdapter::Lazy - Lazy loader for Cpanel::LoggerAdapter

=head1 SYNOPSIS

    use Cpanel::LoggerAdapter::Lazy ();

    my $logger = Cpanel::LoggerAdapter::Lazy->new();

=head1 DESCRIPTION

This module will load Cpanel::LoggerAdapter and
the underlying Cpanel::Logger when the first entry is logged.  This is useful
for cases where logging is not the expected case as it allows the system to avoid
loading these modules when nothing is ever going to be logged.

=head1 FUNCTIONS

=head2 new($args_ref)

Create a C<Cpanel::LoggerAdapter::Lazy> object.  Anything passed in
$args_ref will later be passed to C<Cpanel::LoggerAdapter::new> if a logger
object is created.

=cut

our $_ACTUAL_CLASS = 'Cpanel::LoggerAdapter';

sub new {
    my ( $class, $args_ref ) = @_;

    # SEC-494:  We cannot be lazy in queueprocd only Cpanel::ServerTasks
    return bless { _args => $args_ref }, $class;
}

=head2 info()

See C<Cpanel::LoggerAdapter::info> and C<Cpanel::Logger::info>

=cut

sub info {
    my $self = shift;
    return $self->_load( 'info', @_ );
}

=head2 warn()

See C<Cpanel::LoggerAdapter::warn> and C<Cpanel::Logger::warn>

=cut

sub warn {
    my $self = shift;
    return $self->_load( 'warn', @_ );
}

=head2 throw()

See C<Cpanel::LoggerAdapter::throw>

=cut

sub throw {
    my $self = shift;
    return $self->_load( 'throw', @_ );
}

=head2 notify()

See C<Cpanel::LoggerAdapter::notify>

=cut

sub notify {
    my $self = shift;
    return $self->_load( 'notify', @_ );
}

sub _load {    ## no critic qw(Subroutines::RequireArgUnpacking)
    my $self     = shift;
    my $funcname = shift;

    # Ensure that require() doesn’t clobber something important.
    local ( $@, $! );

    require Cpanel::LoggerAdapter;    # PPI USE OK - blessed below
    require Cpanel::Logger::Persistent;

    $self->{'_logger'} = Cpanel::Logger::Persistent->new( $self->{'_args'} );

    bless $self, $_ACTUAL_CLASS;
    return $self->$funcname(@_);
}

1;    # Magic true value required at end of module
