package Cpanel::DKIM::Load;

# cpanel - Cpanel/DKIM/Load.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::DKIM::Load - DKIM read logic

=head1 SYNOPSIS

    my $path = Cpanel::DKIM::Load::get_key_path( 'public', 'example.com' );

    my $pem = Cpanel::DKIM::Load::get_private_key_if_exists('example.com');

=head1 DESCRIPTION

This module contains logic to read DKIM keys from disk.

=cut

#----------------------------------------------------------------------

use Cpanel::ConfigFiles ();
use Cpanel::LoadFile    ();

#----------------------------------------------------------------------

=head2 $path = get_key_path( $TYPE, $DOMAIN )

Returns the filesystem path of $DOMAIN’s stored DKIM key of type $TYPE
(either C<public> or C<private>).

B<NOTE:> This function breaks the storage system abstraction and should
be called externally as seldom as possible.

=cut

sub get_key_path {
    my ( $type, $domain ) = @_;

    die "Invalid type: “$type”"     if -1 != index( $type,   '/' );
    die "Invalid domain: “$domain”" if -1 != index( $domain, '/' );

    return "$Cpanel::ConfigFiles::DOMAIN_KEYS_ROOT/$type/$domain";
}

#----------------------------------------------------------------------

=head2 $pem = get_private_key_if_exists( $DOMAIN )

Returns $DOMAIN’s private key, or undef if no such key exists.

Throws an appropriate L<Cpanel::Exception> subclass instance if
a failure occurs.

=cut

sub get_private_key_if_exists {
    my ($domain) = @_;

    return Cpanel::LoadFile::load_if_exists( get_key_path( "private", $domain ) );
}

1;
