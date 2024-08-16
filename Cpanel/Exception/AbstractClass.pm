package Cpanel::Exception::AbstractClass;

# cpanel - Cpanel/Exception/AbstractClass.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::Exception::AbstractClass

=head1 SYNOPSIS

    die Cpanel::Exception::create('AbstractClass', [__PACKAGE__]);

=head1 DISCUSSION

This “special snowflake” exception class doesn’t parse exception parameters
the way most other exception classes do. It’s a legacy thing. Please do not
emulate in new code!

=cut

use strict;
use warnings;

use parent qw( Cpanel::Exception );

use Cpanel::LocaleString ();

sub _default_phrase {
    my ( $class, $mt_args_ar ) = @_;

    return Cpanel::LocaleString->new(
        '“[_1]” is an abstract base class. Please use an implementation!',
        $mt_args_ar->[0],
    );
}

1;
