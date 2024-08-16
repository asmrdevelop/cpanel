package Cpanel::MysqlUtils::Password;

# cpanel - Cpanel/MysqlUtils/Password.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::MysqlUtils::Password

=head1 SYNOPSIS

    my $hash = native_password_hash( $raw_password );

=head1 DESCRIPTION

This module contains logic to hash passwords as MySQL implements it.

For similar logic for PostgreSQL, look at L<Cpanel::PostgresUtils::Authn>.

=cut

#----------------------------------------------------------------------

use Digest::SHA1 ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $hash = native_password_hash( $PASSWORD )

Returns a hash of $PASSWORD according to the MySQL 4.1+ “native” method.

=cut

sub native_password_hash {
    my ($pw) = @_;

    return '*' . ( Digest::SHA1::sha1_hex( Digest::SHA1::sha1($pw) ) =~ tr<a-f><A-F>r );
}

1;
