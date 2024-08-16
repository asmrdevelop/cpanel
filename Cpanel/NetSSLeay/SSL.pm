package Cpanel::NetSSLeay::SSL;

# cpanel - Cpanel/NetSSLeay/SSL.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use parent qw( Cpanel::NetSSLeay::Base );

use Cpanel::Context ();

use constant {
    _new_func  => 'new',
    _free_func => 'free',
};

use Cpanel::NetSSLeay ();

=encoding utf-8

=head1 NAME

Cpanel::NetSSLeay::SSL - Wrap Net::SSLeay’s SSL objects

=head1 SYNOPSIS

    use Cpanel::NetSSLeay::SSL;
    use Cpanel::NetSSLeay::CTX;

    my $ctx_obj = Cpanel::NetSSLeay::CTX->new();
    my $ssl_obj = Cpanel::NetSSLeay::SSL->new( $ctx_obj );

=head1 DESCRIPTION

A simple wrapper around Net::SSLeay’s SSL objects that ensures we don’t
neglect to do free().

=cut

=head2 new

A wrapper around Net::SSLeay::new

=head3 Input

None

=head3 Output

A Cpanel::NetSSLeay::SSL object

=cut

sub new {
    my ( $class, $ctx_obj ) = @_;

    return $class->SUPER::new( $ctx_obj->PTR() );
}

=head2 get_cipher_list

A wrapper around Net::SSLeay::get_cipher_list

=head3 Input

None

=head3 Output

Returns an array of ciphers

=cut

#Unlike the Net::SSLeay function, this returns a list of the ciphers.
sub get_cipher_list {
    my ($self) = @_;

    Cpanel::Context::must_be_list();

    my @ciphers;

    while ( my $c = Cpanel::NetSSLeay::do( 'get_cipher_list', $self->PTR(), 0 + @ciphers ) ) {
        push @ciphers, $c;
    }

    return @ciphers;
}

=head2 write_all

A wrapper around Net::SSLeay::write_all

=head3 Input

=over

=item C<SCALAR>

    The payload to write

=back

=head3 Output

The return from Net::SSLeay::write_all

=cut

# no copy of $_[1] since it may be large
# $_[0] = $self
# $_[1] = $payload
sub write_all {
    return Cpanel::NetSSLeay::do( 'ssl_write_all', $_[0]->PTR(), $_[1] );
}

=head2 write_all

A wrapper around Net::SSLeay::set_fd

=head3 Input

=over

=item C<SCALAR>

    The number of the file descriptor to set in the object.

=back

=head3 Output

The return from Net::SSLeay::set_fd

=cut

sub set_fd {
    my ( $self, $fd ) = @_;

    return Cpanel::NetSSLeay::do( 'set_fd', $self->PTR(), $fd );
}

=head2 connect

A wrapper around Net::SSLeay::connect

=head3 Input

None

=head3 Output

The return from Net::SSLeay::connect

=cut

sub connect {
    my ($self) = @_;

    return Cpanel::NetSSLeay::do( 'connect', $self->PTR() );
}

=head2 get_servername

A wrapper around Net::SSLeay::get_servername

=head3 Input

None

=head3 Output

Returns the remotely connected server name.

=cut

sub get_servername {
    my ($self) = @_;

    return Cpanel::NetSSLeay::do( 'get_servername', $self->PTR() );
}

#----------------------------------------------------------------------

=head2 set_tlsext_host_name

Wraps C<Net::SSLeay::set_tlsext_host_name()>. See that function’s
documentation for input/output.

=cut

sub set_tlsext_host_name ( $self, @args ) {
    return Cpanel::NetSSLeay::do(
        'set_tlsext_host_name',
        $self->PTR(),
        @args,
    );
}

#----------------------------------------------------------------------

=head2 set_CTX

A wrapper around Net::SSLeay::set_SSL_CTX

=head3 Input

A Cpanel::NetSSLeay::CTX object

=head3 Output

Returns from Net::SSLeay::set_SSL_CTX

=cut

sub set_CTX {
    my ( $self, $ctx_obj ) = @_;

    return Cpanel::NetSSLeay::do(
        'set_SSL_CTX',
        $self->PTR(),
        $ctx_obj->PTR(),
    );
}

1;
