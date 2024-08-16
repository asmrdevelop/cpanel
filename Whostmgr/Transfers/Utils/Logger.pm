package Whostmgr::Transfers::Utils::Logger;

# cpanel - Whostmgr/Transfers/Utils/Logger.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::Transfers::Utils::Logger

=head1 DESCRIPTION

This module exposes a L<Cpanel::Output>-compatible logger object
for restore modules.

=cut

#----------------------------------------------------------------------

use parent 'Cpanel::Output::Container';

#----------------------------------------------------------------------

=head1 METHODS

The following methods from L<Cpanel::Output> are exposed here:

=over

=item * C<new()>

=item * C<out()> (aka C<info()>)

=item * C<warn()>

=item * C<error()>

=item * C<success()>

=item * C<increase_indent_level()>

=item * C<decrease_indent_level()>

=back

=cut

sub new ( $class, $output_obj ) {
    return bless { _logger => $output_obj }, $class;
}

sub out ( $self, @args ) {
    return $self->_add( 'out', @args );
}

*info = *out;

sub warn ( $self, @args ) {
    return $self->_add( 'warn', @args );
}

sub error ( $self, @args ) {
    return $self->_add( 'error', @args );
}

sub success ( $self, @args ) {
    return $self->_add( 'success', @args );
}

sub increase_indent_level ( $self, @args ) {
    return $self->{'_logger'}->increase_indent_level(@args);
}

sub decrease_indent_level ( $self, @args ) {
    return $self->{'_logger'}->decrease_indent_level(@args);
}

sub _add ( $self, $level, @args ) {
    if ( ref $args[0] && ref $args[0] eq 'ARRAY' ) {
        @args = @{ $args[0] };
    }

    return $self->{'_logger'}->$level( { 'msg' => \@args, 'time' => time() } );
}

1;
