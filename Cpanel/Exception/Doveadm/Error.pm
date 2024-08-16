package Cpanel::Exception::Doveadm::Error;

# cpanel - Cpanel/Exception/Doveadm/Error.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Exception::Doveadm::Error - Failure from doveadm protocol

=head1 SYNOPSIS

    die Cpanel::Exception::create('Doveadm::Error', [ message => $why ]);

=head1 DESCRIPTION

This error class represents server-reported failures from doveadm.

=head1 ATTRIBUTES

=over

=item * C<message> - The response text, i.e., the 1st line of the doveadm
response.

=item * C<status> - The status text, i.e., the 2nd line.

=item * C<command> - Array reference of the command that was sent to
Dovecot that produced this error.

=back

=cut

#----------------------------------------------------------------------

use parent qw( Cpanel::Exception );

use Cpanel::LocaleString ();

#----------------------------------------------------------------------

# tested directly
sub _default_phrase ( $self, @ ) {
    my $cmd_str = join( q< >, @{ $self->get('command') } );

    my $detail = join( q<, >, grep { length } map { $self->get($_) } qw( message status ) );

    return Cpanel::LocaleString->new( '[asis,Dovecot] rejected the request “[_1]” ([_2]).', $cmd_str, $detail );
}

1;
