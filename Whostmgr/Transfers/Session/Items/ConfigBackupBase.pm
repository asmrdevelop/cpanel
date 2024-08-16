package Whostmgr::Transfers::Session::Items::ConfigBackupBase;

# cpanel - Whostmgr/Transfers/Session/Items/ConfigBackupBase.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent 'Whostmgr::Transfers::Session::Item';

our $VERSION = '1.0';

use Whostmgr::Config::Restore ();
use Cpanel::SafeDir::MK       ();

use File::Path ();

sub transfer {
    my ($self) = @_;

    return $self->exec_path(
        [
            '_transfer_init',
            'create_remote_object',
            '_transfer_file',
            ( $self->can('post_transfer') ? 'post_transfer' : () )
        ]
    );
}

sub restore {
    my ($self) = @_;

    return $self->exec_path(
        [
            qw(_restore_config),
            ( $self->can('post_restore') ? 'post_restore' : () ),
        ]
    );
}

sub _restore_config {
    my ($self)       = @_;
    my $restore      = Whostmgr::Config::Restore->new();
    my $restore_file = $self->_get_target_path();
    my %restore_args = (
        'skip_post'   => 0,
        'backup_path' => $restore_file,
        'modules'     => { $self->module_info()->{'config_module'} => ( $self->module_info()->{'config_restore_flags'} || {} ) }
    );

    my ( $status, $statusmsg, $statusref ) = $restore->restore(%restore_args);

    return ( $status, $statusmsg );
}

sub _get_parent_path {
    my ($self) = @_;

    my $session_obj = $self->session();
    my $id          = $session_obj->id();
    my $path        = "/home/$id";

    return $path;
}

sub _get_base_path {
    my ($self) = @_;

    my $path = $self->_get_parent_path() . "/ConfigBackup";

    return $path;
}

sub _get_target_path {
    my ($self) = @_;

    my $path = $self->_get_base_path();
    if ( !-e $path ) {
        Cpanel::SafeDir::MK::safemkdir( $path, 0700 ) or die "Failed to mkdir: $path";
    }

    my $file = "$path/" . $self->item_name() . ".tar.gz";
    return $file;
}

sub _transfer_init {
    my ($self) = @_;

    $self->session_obj_init();

    foreach my $required_object (qw(session_obj output_obj authinfo remote_info)) {
        if ( !defined $self->{$required_object} ) {
            return ( 0, [ "“[_1]” failed to create “[_2]”", ( caller(0) )[3], $required_object ] );
        }
    }

    return ( 1, "All required objects loaded" );
}

sub _transfer_file {
    my ($self) = @_;

    $self->{'output_obj'}->set_source( { 'host' => $self->{'remote_info'}->{'sshhost'} } );
    my ( $status, $statusmsg, undef, undef, undef, undef, undef, $output ) = $self->{'remoteobj'}->remoteexec(
        'txt' => 'Creating config package on remote server',
        'cmd' => "/usr/local/cpanel/bin/cpconftool --backup --modules=" . $self->module_info()->{'config_module'}
    );
    $self->{'output_obj'}->set_source();
    $self->set_percentage(25);

    if ( !$status ) {
        return ( 0, $statusmsg );
    }

    my ($remote_path) = $output =~ m{(/.*\.tar\.gz)\n?$}s;

    if ( !$remote_path ) {
        return ( 0, $self->_locale()->maketext("Could not determine remote path from cpconftool run.") );
    }

    my $restore_file = $self->_get_target_path();

    # We do this rather than scp because scp would happen outside
    # any privilege escalation we need to do.
    ( $status, $statusmsg, undef, undef, undef, undef, undef, $output ) = $self->{'remoteobj'}->remoteexec(
        'txt'          => $self->_locale()->maketext("Copying config package file …"),
        'cmd'          => "base64 $remote_path",
        'returnresult' => 1,
    );

    if ( !$status ) {
        return ( 0, $self->_locale()->maketext( 'The system failed to transfer “[_1]” from the remote server because of an error: [_2]', $remote_path, $statusmsg ) );
    }

    require MIME::Base64;
    my $bin = MIME::Base64::decode($output);

    require Cpanel::FileUtils::Write;
    require Cpanel::OrDie;

    ( $status, $statusmsg ) = Cpanel::OrDie::convert_die_to_multi_return(
        sub {
            Cpanel::FileUtils::Write::overwrite( $restore_file, $bin );
        }
    );

    if ( !$status ) {
        return ( 0, $self->_locale()->maketext( 'The system failed to write the file “[_1]” because of an error: [_2]', $restore_file, $statusmsg ) );
    }

    return ( 1, 'Transferred' );

}

1;
