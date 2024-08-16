package Cpanel::FileUtils::Read::IteratorBase;

# cpanel - Cpanel/FileUtils/Read/IteratorBase.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Try::Tiny;

use Cpanel::Exception ();

sub new {
    my ( $class, $fh, $todo_cr ) = @_;

    my $self = bless {
        _fh      => $fh,
        _todo_cr => $todo_cr,

        #_iteration_index_sr gets set in _run().
    }, $class;

    return $self->_run();
}

sub get_iteration_index {
    my ($self) = @_;

    return ${ $self->{'_iteration_index_sr'} };
}

sub stop {
    my ($self) = @_;

    die Cpanel::FileUtils::Read::IteratorBase::_STOP->new();
}

sub _run_try_catch {
    my ( $self, $try_cr ) = @_;

    local $!;
    try { $try_cr->() }
    catch {
        die $_ if !UNIVERSAL::isa( $_, __PACKAGE__ . '::_STOP' );
    };

    if ($!) {
        die Cpanel::Exception::create( $self->_READ_ERROR_EXCEPTION_CLASS(), [ path => '?', error => $! ] );
    }

    return 1;
}

package Cpanel::FileUtils::Read::IteratorBase::_STOP;

sub new {
    my ($class) = @_;

    my $scalar;
    my $self = \$scalar;
    return bless $self, $class;
}

1;
