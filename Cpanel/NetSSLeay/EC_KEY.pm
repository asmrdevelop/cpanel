package Cpanel::NetSSLeay::EC_KEY;

# cpanel - Cpanel/NetSSLeay/EC_KEY.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::NetSSLeay::Base );

use Cpanel::NetSSLeay ();

use constant {
    _new_func  => 'EC_KEY_new_by_curve_name',
    _free_func => 'EC_KEY_free',
};

=encoding utf-8

=head1 NAME

Cpanel::NetSSLeay::EC_KEY - Write Net::SSLeay’s EC_KEY objects

=head1 SYNOPSIS

    use Cpanel::NetSSLeay::EC_KEY;

    my $ec_key_obj = Cpanel::NetSSLeay::EC_KEY->new('prime256v1');

    $ctx_obj->set_tmp_ecdh($ec_key_obj);

=head1 DESCRIPTION

A simple wrapper around Net::SSLeay’s EC_KEY objects that ensures we don’t
neglect to do EC_KEY_free().

=cut

=head2 new

Create a new Cpanel::NetSSLeay::EC_KEY object

=over 2

=item Input

=over 3

=item C<SCALAR>

The curve name (ex. C<secp384r1>).

=back

=item Output

=over 3

=item A Cpanel::NetSSLeay::EC_KEY object

=back

=back

=cut

sub new {
    my ( $class, $curve ) = @_;

    #Despite the fact that OpenSSL’s function to create an EC_KEY
    #object is named “EC_KEY_new_by_curve_name”, this function
    #expects an NID, not a string. <grumble> …
    $curve = Cpanel::NetSSLeay::do( 'OBJ_txt2nid', $curve );

    return bless $class->SUPER::new($curve), $class;
}

1;
