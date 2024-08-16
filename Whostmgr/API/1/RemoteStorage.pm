package Whostmgr::API::1::RemoteStorage;

# cpanel - Whostmgr/API/1/RemoteStorage.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::API::1::RemoteStorage

=head1 SYNOPSIS

See API docs.

=head1 DESCRIPTION

This module exposes APIs for interaction with cPanel & WHM’s remote-storage
subsystem.

=cut

#----------------------------------------------------------------------

use Cpanel::Imports;

use Whostmgr::API::1::Utils ();

use Cpanel::APICommon::Error ();
use Cpanel::NFS              ();
use Cpanel::RemoteStorage    ();
use Cpanel::Try              ();

use constant NEEDS_ROLE => {
    PRIVATE_add_nfs_storage       => 'CloudController',
    PRIVATE_update_nfs_storage    => 'CloudController',
    PRIVATE_get_remote_storage    => 'CloudController',
    PRIVATE_remove_remote_storage => 'CloudController',
};

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 PRIVATE_add_nfs_storage

See API docs.

=cut

sub PRIVATE_add_nfs_storage ( $args, $metadata, @ ) {
    my $host        = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'host' );
    my $export_path = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'remote_path' );

    my @opts = Whostmgr::API::1::Utils::get_length_arguments( $args, 'option' );

    my $comment = $args->{'comment'};
    if ( my $err = Cpanel::RemoteStorage::get_comment_error($comment) ) {
        $metadata->set_not_ok($err);
        return;
    }

    if ( my @probs = Cpanel::NFS::get_new_mount_problems( $host, $export_path, @opts ) ) {
        $metadata->set_not_ok("Unusable NFS mount: @probs");

        return Cpanel::APICommon::Error::convert_to_payload(
            'nfs_misconfigured',
            problems => \@probs,
        );
    }

    my $local_path = Cpanel::RemoteStorage::add_nfs( $host, $export_path, \@opts, $comment );

    $metadata->set_ok();

    return {
        local_path => $local_path,
    };
}

=head2 PRIVATE_update_nfs_storage

See API docs.

=cut

sub PRIVATE_update_nfs_storage ( $args, $metadata, @ ) {
    my $local_path = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'local_path' );

    my $revision    = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'revision' );
    my $host        = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'host' );
    my $remote_path = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'remote_path' );
    my @opts        = Whostmgr::API::1::Utils::get_length_arguments( $args, 'option' );

    my $comment = $args->{'comment'};
    if ( my $err = Cpanel::RemoteStorage::get_comment_error($comment) ) {
        $metadata->set_not_ok($err);
        return;
    }

    my $probs_hr = Cpanel::NFS::get_update_mount_problems( $local_path, $host, $remote_path, @opts );
    if ( my @prob_names = sort keys %$probs_hr ) {
        $metadata->set_not_ok("Unusable NFS mount: @prob_names");

        return Cpanel::APICommon::Error::convert_to_payload(
            'nfs_misconfigured',
            problems => $probs_hr,
        );
    }

    my $retval;

    Cpanel::Try::try(
        sub {
            my $revision = Cpanel::RemoteStorage::update_nfs(
                $local_path,
                $revision,
                host        => $host,
                remote_path => $remote_path,
                options     => \@opts,
                comment     => $comment,
            );

            $retval = { revision => $revision };

            $metadata->set_ok();
        },
        'Cpanel::Exception::Stale' => sub ($err) {
            $retval = Cpanel::APICommon::Error::convert_to_payload('Stale');
            $metadata->set_not_ok($err);
        },
    );

    return $retval;
}

=head2 PRIVATE_get_remote_storage

See API docs.

=cut

sub PRIVATE_get_remote_storage ( $, $metadata, @ ) {
    my @storage = Cpanel::RemoteStorage::get();

    $metadata->set_ok();

    # This value should output as a string, not a number.
    # As of this writing we implement this value as a simple increasing
    # but we don’t guarantee that.
    #
    $_->{'revision'} .= q<> for @storage;

    return { payload => \@storage };
}

=head2 PRIVATE_remove_remote_storage

See API docs.

=cut

sub PRIVATE_remove_remote_storage ( $args, $metadata, @ ) {
    my $local_path = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'local_path' );

    Cpanel::RemoteStorage::remove($local_path);

    $metadata->set_ok();

    return;
}

1;
