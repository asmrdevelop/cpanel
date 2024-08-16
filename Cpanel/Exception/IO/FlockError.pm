package Cpanel::Exception::IO::FlockError;

# cpanel - Cpanel/Exception/IO/FlockError.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::Exception::IO::FlockError

=head1 SYNOPSIS

    Cpanel::Exception::create('IO::FlockError',
        [ error => $!, path => $path, operation => $as_to_flock, ],
    );

=head1 DESCRIPTION

This exception class is for representing errors from Perl’s C<flock()>
built-in. It subclasses L<Cpanel::Exception::IOError>.

=cut

use strict;
use warnings;

use parent qw( Cpanel::Exception::IOError );

use Cpanel::Fcntl::Constants ();
use Cpanel::LocaleString     ();

use constant FLAG_ORDER => qw(
  LOCK_SH
  LOCK_EX
  LOCK_UN
  LOCK_NB
);

#metadata parameters:
#   error
#   operation   - cf. perldoc -f flock
#   path        - optional
#
sub _default_phrase {
    my ($self) = @_;

    my $op    = $self->get('operation');
    my @flags = _op_to_flags($op);

    if ( $op & $Cpanel::Fcntl::Constants::LOCK_UN ) {
        if ( $self->get('path') ) {
            return Cpanel::LocaleString->new(
                'The system failed to unlock ([join,~, ,_1]) the file “[_2]” because of an error: [_3]',
                \@flags,
                $self->get('path'),
                $self->get('error'),
            );
        }

        return Cpanel::LocaleString->new(
            'The system failed to unlock ([join,~, ,_1]) an unknown file because of an error: [_2]',
            \@flags,
            $self->get('error'),
        );
    }

    if ( $self->get('path') ) {
        return Cpanel::LocaleString->new(
            'The system failed to lock ([join,~, ,_1]) the file “[_2]” because of an error: [_3]',
            \@flags,
            $self->get('path'),
            $self->get('error'),
        );
    }

    return Cpanel::LocaleString->new(
        'The system failed to lock ([join,~, ,_1]) an unknown file because of an error: [_2]',
        \@flags,
        $self->get('error'),
    );
}

sub _op_to_flags {
    my ($op) = @_;

    return grep { $op & ${ *{ $Cpanel::Fcntl::Constants::{$_} }{'SCALAR'} } } FLAG_ORDER();
}

1;
