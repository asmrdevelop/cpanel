package Whostmgr::Transfers::Systems::Ftp;

# cpanel - Whostmgr/Transfers/Systems/Ftp.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

# RR Audit: JNK

use Try::Tiny;

use Cpanel::ConfigFiles::Apache 'apache_paths_facade';    # see POD for import specifics
use Cpanel::FtpUtils::Passwd ();
use Cpanel::Exception        ();
use Cpanel::Ftp::Passwd      ();
use Cpanel::ServerTasks      ();
use Cpanel::LoadFile         ();
use Cpanel::Locale           ();
use Cpanel::Path::Dir        ();
use Cwd                      ();
use File::Spec               ();

use base qw(
  Whostmgr::Transfers::Systems
);

my $FTP_SHELL             = '/bin/ftpsh';
my $FTP_PASSWD_FILE_PERMS = 0640;

sub get_prereq {
    return ['Shell'];
}

sub get_summary {
    my ($self) = @_;
    return [ $self->_locale()->maketext('This restores [output,abbr,FTP,File Transfer Protocol] accounts.') ];
}

sub get_restricted_available {
    return 1;
}

sub _parse_ftp_passwd_file_contents {
    my ( $self, $contents_sr ) = @_;

    my ( $accts_obj, $err );

    try {
        $accts_obj = Cpanel::Ftp::Passwd->new($contents_sr);
    }
    catch {
        chomp $_;
        $err = $_;
    };

    return ( 0, $err ) if $err;

    return ( 1, $accts_obj );
}

sub _read_ftp_passwd_file {
    my ($self) = @_;

    if ( !$self->{'_contents_sr'} ) {
        my $extractdir = $self->extractdir();

        my $ftp_file_path = "$extractdir/proftpdpasswd";

        #TODO: Max size of FTP file .. ?
        return 1 if !-s $ftp_file_path;

        my $contents_sr = Cpanel::LoadFile::loadfile_r($ftp_file_path) or do {
            return ( 0, $self->_locale()->maketext( 'The system failed to load the file “[_1]” because of an error: [_2]', $ftp_file_path, $! ) );
        };

        $self->{'_contents_sr'} = $contents_sr;
    }

    return ( 1, $self->{'_contents_sr'} );
}

#TODO: Replace this with restricted; we should be able to parse everything
#we need from the file and then restore via a batched FTP account creation.
#
#Note: The ftp code needs significant refactoring before this is possible.
#
sub unrestricted_restore {
    my ($self) = @_;

    my ( $read_ok, $contents_sr ) = $self->_read_ftp_passwd_file();
    return ( 0, $contents_sr ) if !$read_ok;

    return 1 if !$contents_sr || !$$contents_sr;    #Nothing to do!

    $self->start_action('Restoring ftp password file');

    my ( $parse_ok, $ftp_accts_obj ) = $self->_parse_ftp_passwd_file_contents($contents_sr);

    return ( 0, "The archive’s FTP passwd file is invalid: " . Cpanel::Exception::get_string($ftp_accts_obj) ) if !$parse_ok;

    my $modified_file_contents_sr = $self->_build_passwd_file_contents_from_ftp_accts_obj($ftp_accts_obj);

    my $newuser = $self->newuser();

    my ( $created, $error ) = Cpanel::FtpUtils::Passwd::create( $newuser, unsuspend => 1, return_errors => 1, content => $$modified_file_contents_sr );
    return ( 0, "The system failed to restore FTP accounts for $newuser: $error" ) unless ($created);

    $self->start_action('Resyncing FTP Passwords');
    $self->out( Cpanel::ServerTasks::schedule_task( ['CpDBTasks'], 10, "ftpupdate" ) );

    return 1;
}

sub _build_passwd_file_contents_from_ftp_accts_obj {
    my ( $self, $ftp_accts_obj ) = @_;

    my $olduser = $self->olduser();
    my $newuser = $self->newuser();
    my ( $uid, $gid, $homedir, $shell ) = ( $self->{'_utils'}->pwnam() )[ 2, 3, 7, 8 ];
    my $local_username_is_different_from_original_username = $self->local_username_is_different_from_original_username() ? 1 : 0;
    my ( $old_ok, $oldhomedirs_ref ) = $self->{'_archive_manager'}->get_old_homedirs();
    my @normalized_old_homedirs;
    if ($old_ok) {
        foreach my $oldhomedir (@$oldhomedirs_ref) {
            my $normalized_dir          = Cpanel::Path::Dir::normalize_dir($oldhomedir);
            my $abs_path_normalized_dir = Cwd::abs_path($normalized_dir);                                                  # returns undef on error
            my $normalized_old_homedir  = defined $abs_path_normalized_dir ? $abs_path_normalized_dir : $normalized_dir;
            push @normalized_old_homedirs, $normalized_old_homedir if $normalized_old_homedir =~ m{^/};
        }
    }

    my @lines;
    foreach my $entry ( @{ $ftp_accts_obj->get_entries() } ) {

        # ftpuser
        $entry->migrate_cpusername( $olduser, $newuser ) if $local_username_is_different_from_original_username;
        my $ftpuser = $entry->ftpuser();

        # cryptftppass

        # uid
        $entry->set_ouid($uid);

        # gid
        $entry->set_ogid($gid);

        # owner
        $entry->set_owner($newuser);

        # homedir
        my $normalized_ftp_homdir = Cpanel::Path::Dir::normalize_dir( $entry->homedir() );
        my $previous_homedir      = File::Spec->file_name_is_absolute($normalized_ftp_homdir) ? $normalized_ftp_homdir : '';
        foreach my $normalized_old_homedir (@normalized_old_homedirs) {
            next unless defined $normalized_old_homedir;
            $previous_homedir =~ s{^\Q$normalized_old_homedir\E}{$homedir};
        }

        if ( $ftpuser eq $newuser ) {
            $entry->set_homedir($homedir);
        }
        elsif ( $ftpuser eq $newuser . "_logs" ) {
            $entry->set_homedir( apache_paths_facade->dir_domlogs() . "/$newuser" );
        }
        elsif ( $previous_homedir =~ m{^\Q$homedir\E} ) {
            $entry->set_homedir($previous_homedir);
        }
        else {
            $entry->set_homedir("$homedir/public_html/$ftpuser");
        }

        # shell
        my $ftp_user_shell = $entry->shell();
        if ( $ftpuser ne $newuser || $ftp_user_shell =~ m{(?:noshell|nologin|false|shutdown|sync|ftp)} || $shell =~ m{(?:noshell|nologin|false|shutdown|sync|ftp)} ) {
            $entry->set_shell($FTP_SHELL);
        }
        else {
            $entry->set_shell($shell);
        }

        # Now stringify
        push @lines, $entry->to_string();
    }

    return \join( "\n", @lines );
}

*restricted_restore = \&unrestricted_restore;

1;
