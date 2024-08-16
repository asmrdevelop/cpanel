package Whostmgr::API::1::PublicContact;

# cpanel - Whostmgr/API/1/PublicContact.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Whostmgr::API::1::PublicContact

=head1 SYNOPSIS

WHM APIs PublicContact

=cut

use Cpanel::LoadModule         ();
use Cpanel::PublicContact      ();
use Cpanel::PublicContact::WHM ();

use Whostmgr::API::1::Utils ();

use constant NEEDS_ROLE => {
    get_public_contact => undef,
    set_public_contact => undef,
};

=head1 FUNCTIONS

=head2 get_public_contact()

Returns the operating reseller’s public contact information
as a hash reference. Each public contact item (e.g., C<name>, C<url>)
is present, at least as an empty string.

L<https://go.cpanel.net/get_public_contact>

=cut

sub get_public_contact {
    my ( $args, $metadata ) = @_;

    my $info = Cpanel::PublicContact->get( _get_pc_user() );

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return $info;
}

=head2 set_public_contact()

Sets public contact values for the operating reseller.

At least one of the following parameters must be passed:

=over

=item * C<name> - An arbitrary name.

=item * C<url> - A contact URL.

=back

Note that undefined/null or missing values are ignored—i.e., the
value is left unchanged. To set a value to empty, send in the
empty string.

L<https://go.cpanel.net/set_public_contact>

=cut

sub set_public_contact {
    my ( $args, $metadata ) = @_;

    Cpanel::LoadModule::load_perl_module('Cpanel::PublicContact::Write');

    Cpanel::PublicContact::Write->set( _get_pc_user(), %$args );

    # Also clear login page cache. Not using glob due to not wanting to import
    # File::Glob just for this. Pattern is simple enough that "a glob is ok"
    # but generally we don't like glob in compiled contexts. Skip if we cannot
    # open the dir, as it probably just doesn't exist then.
    my $cache_dir = "/var/cpanel/caches/showtemplate.stor";
    if ( opendir( my $dh, $cache_dir ) ) {
        unlink "$cache_dir/$_" or warn "Can't clear cache file $cache_dir/$_: $!" for grep { index( $_, 'login_template_' ) == 0 } readdir($dh);
    }

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return;
}

*_get_pc_user = *Cpanel::PublicContact::WHM::get_pc_user;

1;
