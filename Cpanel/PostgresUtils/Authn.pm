package Cpanel::PostgresUtils::Authn;

# cpanel - Cpanel/PostgresUtils/Authn.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::PostgresUtils::Authn

=head1 SYNOPSIS

    my $hash = create_md5_user_password_hash( 'dbusername', $password );

=head1 DESCRIPTION

This module contains logic to hash passwords as PostgreSQL implements it.

For similar logic for MySQL, look at L<Cpanel::MysqlUtils::Password>.

=cut

#----------------------------------------------------------------------

use Digest::MD5 ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $md5_hash = create_md5_user_password_hash( $DB_USERNAME => $PASSWORD )

This applies PostgreSQL’s MD5-based password hashing algorithm to the given
username and password. The returned string is suitable for insertion into
a C<CREATE USER> command.

Note that PostgreSQL 10.0+ encourages
L<SCRAM-SHA-256|https://tools.ietf.org/html/rfc7677> rather than the older
MD5-based hashing implemented here; however, cPanel & WHM doesn’t currently
support a new enough PostgreSQL version to use this.

The logic is derived from L<this forum post|https://stackoverflow.com/questions/14918763/generating-postgresql-user-password> and confirmed manually.

=cut

sub create_md5_user_password_hash {
    my ( $username, $pw ) = @_;

    die 'Give username and password.' if !length $username || !length $pw;

    return 'md5' . Digest::MD5::md5_hex( $pw . $username );
}

1;
