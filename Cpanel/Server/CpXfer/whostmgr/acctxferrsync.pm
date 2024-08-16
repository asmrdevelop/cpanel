package Cpanel::Server::CpXfer::whostmgr::acctxferrsync;

# cpanel - Cpanel/Server/CpXfer/whostmgr/acctxferrsync.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Server::CpXfer::whostmgr::acctxferrsync

=head1 DESCRIPTION

This module implements acctxferrsync for WHM.

Only root may call this module. (It would be fine to extend it later
to allow non-root resellers, but we don’t currently need that functionality.)
Thus, a C<username> must be given in the request URL’s query string.
Note that this username need not refer to a cPanel user; it can be the
name of any user that exists on the system.

This module subclasses L<Cpanel::Server::CpXfer::Base::acctxferrsync>.

=cut

#----------------------------------------------------------------------

use parent qw( Cpanel::Server::CpXfer::Base::acctxferrsync );

use Cpanel::Exception      ();
use Cpanel::PwCache        ();
use Cpanel::PwCache::Group ();
use Whostmgr::ACLS         ();

#----------------------------------------------------------------------

=head1 METHODS

=head2 I<CLASS>->verify_access()

Returns 1 if the WHM user has root access.
Throws L<Cpanel::Exception::cpsrvd::Forbidden> otherwise.

=cut

sub verify_access {
    Whostmgr::ACLS::init_acls();

    if ( Whostmgr::ACLS::hasroot() ) {
        return 1;
    }

    die Cpanel::Exception::create('cpsrvd::Forbidden');
}

sub _get_homedir {
    my ( $self, $form_ref ) = @_;

    my $err;

    my $username = $form_ref->{'username'};

    if ( !length $username ) {
        $err = 'Need “username”!';
    }
    else {
        my ( $xferuid, $xfergid, $user_homedir ) = ( Cpanel::PwCache::getpwnam_noshadow($username) )[ 2, 3, 7 ];

        if ( !defined $xferuid ) {
            $err = "“$username” is not a user on this system.";
        }
        else {
            my $server_obj = $self->get_server_obj();

            my @supplemental_gids = Cpanel::PwCache::Group::get_supplemental_gids_for_user($username);
            $server_obj->switchuser( $username, $xferuid, $xfergid, @supplemental_gids );    #will die if fails

            return $user_homedir;
        }
    }

    die Cpanel::Exception::create_raw( 'cpsrvd::BadRequest', $err );
}

1;
