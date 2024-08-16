package Whostmgr::Transfers::Systems::SpamAssassin;

# cpanel - Whostmgr/Transfers/Systems/SpamAssassin.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use base 'Whostmgr::Transfers::Systems';

use Cpanel::AccessIds::ReducedPrivileges   ();
use Cpanel::Services::Enabled              ();
use Cpanel::Autodie                        ();
use Cpanel::FileUtils::TouchFile           ();
use Cpanel::Server::Type::Role::SpamFilter ();
use Cpanel::PwCache                        ();

=encoding utf-8

=head1 NAME

Whostmgr::Transfers::Systems::SpamAssassin

=head1 SYNOPSIS

This module is a part of the Transfer/Restore system.
See Whostmgr::Transfers::System and Whostmgr::Transfers::AccountRestoration

=head1 DESCRIPTION

If SpamAssassin is disabled on the local system, this module will detect if
it was enabled for the source user, and disable if needed.

=head1 FUNCTIONS

=cut

=head2 get_prereq()

This function returns an arrayref of Transfer/Restore system component
names that should be called before this module in execution of the
Transfer/Restore

=head3 Arguments

None.

=head3 Returns

This function returns an arrayref of prerequisite components.

=head3 Exceptions

None.

=cut

sub get_prereq {
    return ['Homedir'];
}

*unrestricted_restore = \&restricted_restore;

=head2 restricted_restore()

This class method is the workhorse of the module. This function is used
by the Transfer/Restore system to disable spamassassin for the user if
it spamd is disabled on the system.

=head3 Arguments

None.

=head3 Returns

This function returns a two-part array return of ( 1, $msg ) when the function succeeds.

=head3 Exceptions

Anything the archive manager can throw.
Anything makeZ<>text can throw.

=cut

sub restricted_restore {
    my ($self) = @_;

    if ( !Cpanel::Services::Enabled::is_enabled('spamd') ) {

        if ( $self->_disable_spamassassin_as_user() ) {

            # Don’t warn if the role is disabled.
            if ( Cpanel::Server::Type::Role::SpamFilter->is_enabled() ) {
                $self->out( $self->_locale()->maketext('This system does not have SpamAssassin enabled, so it has been disabled for this user.') );
            }
        }
    }

    return ( 1, 'Ran SpamAssassin check' );
}

=head2 _disable_spamassassin_as_user()

This function drops to the user's provileges and,
if the .spamassassinenable exists, deletes it and
creates the .spamassassindisabled file

=head3 Arguments

None.

=head3 Returns

Returns true if it created the .spamassassindisabled,
false if not.

=head3 Exceptions

Anything ReducedPrivileges, Unlink, or TouchFile can throw.

=cut

sub _disable_spamassassin_as_user {
    my ($self) = @_;

    my ( $user_uid, $user_gid, $homedir ) = ( Cpanel::PwCache::getpwnam( $self->newuser() ) )[ 2, 3, 7 ];

    # Drop privileges to read/write the directory as the user
    my $reduced_privs_guard = Cpanel::AccessIds::ReducedPrivileges->new( $user_uid, $user_gid );

    if ( Cpanel::Autodie::unlink_if_exists(qq{$homedir/.spamassassinenable}) ) {

        Cpanel::FileUtils::TouchFile::touchfile(qq{$homedir/.spamassassindisabled});
        return 1;
    }

    return 0;
}

=head2 get_summary()

This function returns an arrayref of localized descriptions for
this Transfer/Restore component.

=head3 Arguments

None.

=head3 Returns

An arrayref of localized strings.

=head3 Exceptions

Anything maketext can throw.

=cut

sub get_summary {
    my ($self) = @_;
    return [ $self->_locale()->maketext('This module will disable SpamAssassin for the restored user if they had it enabled at the source.') ];
}

1;
