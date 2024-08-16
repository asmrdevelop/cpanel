package Cpanel::Crypt::Algorithm;

# cpanel - Cpanel/Crypt/Algorithm.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Crypt::Algorithm

=head1 SYNOPSIS

If you have an object such as L<Cpanel::SSL::Objects::Certificate>
or L<Cpanel::SSL::Parsed::Key>:

    Cpanel::Crypt::Algorithm::dispatch_from_object(
        $obj,
        rsa => sub { ... },
        ecdsa => sub { ... },
    );

… or, if you have just a plain hashref:

    # This mimics the structure returned from, e.g.,
    # Cpanel::SSL::Utils::parse_certificate_text(); however,
    # that function now returns a Cpanel::SSL::Parsed::Certificate
    # instance, so only use this if you have the plain hash:
    my $parse_hr = {
        key_algorithm => Cpanel::Crypt::Constants::ALGORITHM_RSA,
    };

    Cpanel::Crypt::Algorithm::dispatch_from_parse(
        $parse_hr,
        rsa => sub { ... },
        ecdsa => sub { ... },
    );

=head1 DESCRIPTION

Logic for cryptography that handles multiple algorithms.

=cut

#----------------------------------------------------------------------

use Cpanel::Crypt::Constants ();

my %DISPATCH_NAME = (
    Cpanel::Crypt::Constants::ALGORITHM_RSA()   => 'rsa',
    Cpanel::Crypt::Constants::ALGORITHM_ECDSA() => 'ecdsa',
);

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 ? = dispatch_from_parse( \%PARSE, %DISPATCH )

Runs a callback in %DISPATCH depending on the C<key_algorithm> in %PARSE.
That C<key_algorithm>’s value will be the value of one of the
C<ALGORITHM_*> constants in L<Cpanel::Crypt::Constants>.

%DISPATCH should include callbacks for:

=over

=item * C<rsa>

=item * C<ecdsa>

=back

B<NOTE:> %PARSE is given as a I<reference>. It should normally correspond
to one of the hashes returned from the parsers in L<Cpanel::SSL::Utils>.
It’s also compatible with the C<find_*()> return hashes from
L<Cpanel::SSLStorage>.

If %DISPATCH lacks the needed callback, or if %PARSE’s C<key_algorithm>
isn’t a recognized value, an exception is thrown.

The callback receives \%PARSE as an argument.

The return value is whatever the relevant callback returns.

=cut

#----------------------------------------------------------------------

sub dispatch_from_parse ( $parse_hr, @dispatch_kv ) {
    my $algo = $parse_hr->{'key_algorithm'} or do {
        die 'need “key_algorithm”!';
    };

    return _dispatch_algo( $algo, $parse_hr, @dispatch_kv );
}

#----------------------------------------------------------------------

=head2 ? = dispatch_from_object( $OBJECT, %DISPATCH )

Like C<dispatch_from_parse()>, but the first argument is an object
rather than a hash reference. ($OBJECT is the callback argument.)
That object’s C<key_algorithm()> method is called in lieu of looking up
a hash property.

Compatible $OBJECT classes include L<Cpanel::SSL::Objects::Certificate>.

=cut

sub dispatch_from_object ( $obj, @dispatch_kv ) {
    my $algo = $obj->key_algorithm();

    return _dispatch_algo( $algo, $obj, @dispatch_kv );
}

#----------------------------------------------------------------------

sub _dispatch_algo ( $algo, $arg, %dispatch ) {
    my $algo_key = $DISPATCH_NAME{$algo} or do {
        die "Unknown key algorithm: “$algo”";
    };

    my $cb = $dispatch{$algo_key} or do {
        die "No “$algo_key” callback given!";
    };

    return $cb->($arg);
}

1;
