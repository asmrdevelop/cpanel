package Cpanel::Exception::NetSSLeay;

# cpanel - Cpanel/Exception/NetSSLeay.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# An exception class for Net::SSLeay errors.
#----------------------------------------------------------------------

use strict;
use warnings;

use parent qw( Cpanel::Exception );

use Net::SSLeay ();

use Cpanel::Encoder::ASCII ();
use Cpanel::Errno          ();
use Cpanel::LocaleString   ();

my $NET_SSLEAY = 'Net::SSLeay';

sub _default_phrase {
    my ($self) = @_;

    my ( $func, $args_ar, $err_codes, $errno ) = map { $self->get($_) } qw(
      function
      arguments
      error_codes
      errno
    );

    local ( $!, $@ );

    # We want error strings like “fopen” rather than, e.g., “func(13)”.
    Net::SSLeay::load_error_strings();

    my @err_strs = map { Net::SSLeay::ERR_error_string($_) } @$err_codes;

    s<\Aerror:><> for @err_strs;

    @err_strs = map { "$err_codes->[$_] ($err_strs[$_])" } ( 0 .. $#err_strs );

    my @printable_args = map { Cpanel::Encoder::ASCII::to_hex($_) } @$args_ar;

    if ($errno) {
        my $errno_code = Cpanel::Errno::get_name_for_errno_number( 0 + $errno );

        return Cpanel::LocaleString->new(
            '[_1]::[_2]([_3]) produced an operating system error ([_4], [_5]) and [numf,_6] [asis,OpenSSL] [numerate,_6,error,errors]: [join,~, ,_7]',
            $NET_SSLEAY,
            $func,
            "@printable_args",
            $errno_code,
            "$errno",
            0 + @err_strs,
            \@err_strs,
        );
    }

    return Cpanel::LocaleString->new(
        '[_1]::[_2]([_3]) produced [numf,_4] [asis,OpenSSL] [numerate,_4,error,errors]: [join,~, ,_5]',
        $NET_SSLEAY,
        $func,
        "@printable_args",
        0 + @err_strs,
        \@err_strs,
    );
}

1;
