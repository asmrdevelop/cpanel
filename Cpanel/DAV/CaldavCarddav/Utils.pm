
# cpanel - Cpanel/DAV/CaldavCarddav/Utils.pm       Copyright 2024 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
package Cpanel::DAV::CaldavCarddav::Utils;

use cPstrict;

=head1 NAME

Cpanel::DAV::CaldavCarddav::Utils

=head1 DESCRIPTION

These functions duplicate some existing code, not only with other modules, but also between each function.
This is intentional so this module can work without having to load Cpanel::DAV::CaldavCarddav and each function
can be called independantly.

=head1 FUNCTIONS

=head2 clean_user_from_system($sysuser_homedir, $luser, $domain)

Remove all data on disk associated with the specified CalDAV/CardDAV user, including:

=over

=item * Sharing

=item * Proxy

=item * Symlinks (invitations)

=item * The user's own collections

=back

=cut

sub clean_user_from_system {
    my ( $sysuser_homedir, $luser, $domain ) = @_;
    my $user;
    if ( length $domain ) {
        $user = $luser . '@' . $domain;
    }

    # Remove user from .sharing
    clean_user_from_sharing( $sysuser_homedir, $user );

    # Remove user from .proxy_config
    clean_user_from_proxy( $sysuser_homedir, $user );

    # Remove symlinks to events pointing to this user's space
    clean_user_symlinks( $sysuser_homedir, $user );

    # Remove all other user files from .caldav/
    require File::Path;
    File::Path::rmtree( $sysuser_homedir . '/.caldav/' . $user . '/' );

    return;
}

=head2 clean_user_from_sharing($sysuser_homedir, $user)

Remove all collection shares to and from the given user

=cut

sub clean_user_from_sharing {
    my ( $sysuser_homedir, $user ) = @_;
    require Cpanel::DAV::Metadata;

    my $metadata_obj = Cpanel::DAV::Metadata->new(
        'homedir' => $sysuser_homedir,
        'user'    => $user,
    );
    my $sharing_hr = $metadata_obj->load( $sysuser_homedir . '/.caldav/.sharing' );
    foreach my $sharer ( keys %{$sharing_hr} ) {
        my ( $s_user, undef ) = split( /\s+/, $sharer, 2 );
        if ( $s_user eq $user ) {
            delete $sharing_hr->{$sharer};    # remove any shares from the user
        }
        else {
            foreach my $sharedto ( keys %{ $sharing_hr->{$sharer} } ) {
                if ( $sharedto eq $user ) {
                    delete $sharing_hr->{$sharer}{$sharedto};     # remove any shares to the user
                    if ( !keys %{ $sharing_hr->{$sharer} } ) {    # clear newly-emptied sharing sections
                        delete $sharing_hr->{$sharer};
                    }
                }
            }
        }
    }
    $metadata_obj->save( $sharing_hr, $sysuser_homedir . '/.caldav/.sharing' );
    return;
}

=head2 clean_user_from_proxy($sysuser_homedir, $user)

Remove all delegations to and from the given user

=cut

sub clean_user_from_proxy {
    my ( $sysuser_homedir, $user ) = @_;
    require Cpanel::DAV::Metadata;

    my $metadata_obj = Cpanel::DAV::Metadata->new(
        'homedir' => $sysuser_homedir,
        'user'    => $user,
    );
    my $proxy_hr = $metadata_obj->load( $sysuser_homedir . '/.caldav/.proxy_config' );
    delete $proxy_hr->{$user};    # delete and delegations from the user
    foreach my $delegator ( keys %{$proxy_hr} ) {
        foreach my $delegatee ( keys %{ $proxy_hr->{$delegator} } ) {
            if ( $delegatee eq $user ) {
                delete $proxy_hr->{$delegator}{$delegatee};    # remove any delegations to the user
                if ( !keys %{ $proxy_hr->{$delegator} } ) {    # clear newly-emptied delegation sections
                    delete $proxy_hr->{$delegator};
                }
            }
        }
    }
    $metadata_obj->save( $proxy_hr, $sysuser_homedir . '/.caldav/.proxy_config' );
    return;
}

=head2 clean_user_symlinks($sysuser_homedir, $user)

Find and remove all symlinks to events owned by the given user.
Note that we are not removing them from the attendees list of all events on the server as this can already be resource intensive.

=cut

sub clean_user_symlinks {
    my ( $sysuser_homedir, $user ) = @_;
    require File::Find;
    my $regex = qr{/\.caldav/\Q$user\E/};
    File::Find::find(
        sub {
            my $file = $File::Find::name;
            if ( -l $file && ( $file =~ /\.ics$/ ) ) {
                if ( my $orig = readlink($file) ) {

                    # Unlink any paths that are ics files symlinking to the user being removed
                    if ( $orig =~ m/$regex/ ) {
                        _unlink($file);
                    }
                }
            }
        },
        $sysuser_homedir . '/.caldav/'
    );
    return;
}

sub _unlink {
    return unlink shift;
}

1;
