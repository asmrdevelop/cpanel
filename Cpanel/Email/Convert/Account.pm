package Cpanel::Email::Convert::Account;

# cpanel - Cpanel/Email/Convert/Account.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Try::Tiny;
use File::Path                           ();
use Cpanel::Email::Perms                 ();
use Cpanel::Mkdir                        ();
use Cpanel::Chdir                        ();
use Cpanel::Dovecot::Sync                ();
use Cpanel::DiskCheck                    ();
use Cpanel::Exception                    ();
use Cpanel::FileUtils::Symlinks          ();
use Cpanel::AccessIds::ReducedPrivileges ();
use Cpanel::Email::DiskUsage             ();
use Cpanel::Dovecot::Utils               ();
use Cpanel::Email::Maildir::Utils        ();
use Cpanel::Email::Mdbox::Utils          ();
use Cpanel::Email::Mailbox               ();
use Cpanel::Email::Mailbox::Format       ();
use Cpanel::LoadFile                     ();
use Cpanel::FileUtils::Write             ();

# constant
use constant ENABLE_FSYNC  => 0;
use constant DISABLE_FSYNC => 1;

# constant
use constant CONVERT_FAIL    => 0;
use constant CONVERT_SUCCESS => 1;

my $MAX_PID = 4294967294;

our $PRODUCTION = 1;

=pod

=head1 NAME

Cpanel::Email::Convert::Account

=head1 WARNING

This module must never be called directly and should only be
instantiated by Cpanel::Email::Convert::User

=head1 DESCRIPTION

Convert a single email account from one mailbox storage
format to another format.

All interfaces in this module should be considered private
and subject to change at any time.  If you want to use this
functionality, you must call this module from Cpanel::Email::Convert::User

=cut

sub new {
    my ( $class, %opts ) = @_;

    foreach my $required (qw(user_convert_obj email_account)) {
        if ( !length $opts{$required} ) {
            die Cpanel::Exception::create( 'MissingParameter', [ 'name' => $required ] );
        }
    }

    my $user_convert_obj = $opts{'user_convert_obj'};
    if ( !try { $user_convert_obj->isa('Cpanel::Email::Convert::User') } ) {
        die Cpanel::Exception::create( 'InvalidParameter', "The “[_1]” parameter must be a “[_2]” object.", [ 'user_convert_obj', 'Cpanel::Email::Convert::User' ] );
    }
    my $email_account = $opts{'email_account'};

    my $homedir     = $user_convert_obj->homedir();
    my $system_user = $user_convert_obj->system_user();
    if ( $email_account eq $system_user ) {
        die Cpanel::Exception::create( 'InvalidParameter', "The “[_1]” parameter must be in the “[_2]” format.", [ 'email_account', '_mainaccount@domain.tld' ] );
    }

    my $self = {
        'user_convert_obj' => $user_convert_obj,
        'homedir'          => $homedir,
        'email_account'    => $email_account,
        'system_user'      => $system_user,
        'skip_removal'     => $user_convert_obj->skip_removal() ? 1 : 0,
        'maildir'          => Cpanel::Email::DiskUsage::get_maildir_for_email_account( $homedir, $email_account ),
        'target_format'    => $user_convert_obj->target_format(),
        'verbose'          => $user_convert_obj->verbose() ? 1 : 0,
        'is_utf8'          => $opts{'is_utf8'}
    };

    if ( !-d $self->{'maildir'} ) {
        die Cpanel::Exception::create( 'InvalidParameter', "The “[_1]” parameter must refer to an existing account.", ['email_account'] );
    }

    $self->{'source_format'} = $user_convert_obj->source_format() || Cpanel::Email::Mailbox::detect_format( $self->{'maildir'} );

    return bless $self, $class;
}

sub convert {
    my ($self) = @_;

    $self->_check_source_format() or return undef;

    print "Changing directory to “$self->{'maildir'}”.\n" if $self->{'verbose'};
    my $chdir = Cpanel::Chdir->new( $self->{'maildir'} );

    try {
        $self->_create_conversion_in_progress_if_disk_ok();
        print "Cleaning up “$self->{'maildir'}” for “$self->{'email_account'}”.\n" if $self->{'verbose'};
        $self->_cleanup_maildir_for_account();
        for my $pass ( 1 .. 2 ) {
            print "Syncing while existing sessions for “$self->{'email_account'}” are using $self->{'source_format'} (pass $pass).\n" if $self->{'verbose'};
            $self->_dsync_until_status_zero(DISABLE_FSYNC);
        }
        $self->_unlink_conversion_in_progress(CONVERT_SUCCESS);
        print "Flushing the authentication cache for dovecot.\n" if $self->{'verbose'};
        Cpanel::Dovecot::Utils::flush_auth_caches( $self->{'email_account'} );
        print "Bouncing existing session for “$self->{'email_account'}” in order to have them reload in the new format.\n" if $self->{'verbose'};
        Cpanel::Dovecot::Utils::kick( $self->{'email_account'} );

        # Now they are logged in with mdbox
        # Get anything we missed
        print "Syncing again to pickup any new mail that was delivered while the system converted “$self->{'email_account'}” to $self->{'target_format'}.\n" if $self->{'verbose'};
        $self->_dsync_until_status_zero(ENABLE_FSYNC);
        $self->_remove_files_for_mailbox_format( $self->{'source_format'} ) unless $self->{'skip_removal'};

        $self->_setup_symlinks_for_accounts();
        $self->_ensure_mailbox_dirs_exist();
        $self->_clean_up_quota_files();
    }
    catch {
        print "The conversion failed due to an error: " . Cpanel::Exception::get_string($_) . "\n";
        $self->_remove_files_for_mailbox_format( $self->{'target_format'} ) if $PRODUCTION;
        $self->_unlink_conversion_in_progress(CONVERT_FAIL);    # We cannot remove this file until we remove the target files or the next login will start using them

        local $@ = $_;
        die;
    };

    print "$self->{'email_account'}: success\n";

    return 1;
}

sub _clean_up_quota_files {
    my ($self) = @_;

    # We need to unlink this or our disk usage will be incorrect.
    unlink("$self->{'maildir'}/dovecot-quota");
    return 1;
}

sub _ensure_mailbox_dirs_exist {
    my ($self) = @_;

    my $access_ids     = Cpanel::AccessIds::ReducedPrivileges->new( $self->{'system_user'} );
    my @dirs_to_create = Cpanel::Email::Mailbox::Format::get_relative_dirs_to_create( $self->{'target_format'} );
    foreach my $maildir (@dirs_to_create) {
        Cpanel::Mkdir::ensure_directory_existence_and_mode( $self->{'maildir'} . '/' . $maildir, $Cpanel::Email::Perms::MAILDIR_PERMS );
    }
    return 1;

}

sub _setup_symlinks_for_accounts {
    my ($self) = @_;
    if ( $self->{'email_account'} !~ m{^_mainaccount\@} ) {
        if ( $self->{'target_format'} eq 'maildir' ) {
            Cpanel::Email::Maildir::Utils::create_symlink_to_subaccount( $self->{'system_user'}, $self->{'email_account'} );
        }
        else {
            Cpanel::Email::Maildir::Utils::remove_symlink_to_subaccount( $self->{'system_user'}, $self->{'email_account'} );
        }
    }
    return 1;
}

sub _check_source_format {
    my ($self) = @_;

    # Important check as we will end up deleting all their
    # mail if this module is ever called with the source_format
    # being the same as the target_format.
    if ( $self->{'source_format'} eq $self->{'target_format'} ) {
        die "The source format may not be the same as the target format";
    }

    my $is_in_source_format = Cpanel::Email::Mailbox::looks_like_format( $self->{'maildir'}, $self->{'source_format'} );
    my $current_format;
    try {
        $current_format = Cpanel::Email::Mailbox::detect_format( $self->{'maildir'} );
    };

    # If we cannot detect the format this will throw an exception
    # which means its safe to convert to any format.

    if ( !$is_in_source_format && !$current_format ) {

        # detect_format cannot detect the format of an empty mailbox
        # but we can always convert an empty mailbox to the format
        # of our choice
        return 1;
    }
    elsif ( !$is_in_source_format ) {
        print "$self->{'email_account'}: not in $self->{'source_format'} format\n";
        return 0;
    }

    return 1;
}

sub _cleanup_maildir_for_account {
    my ($self) = @_;

    my $access_ids = Cpanel::AccessIds::ReducedPrivileges->new( $self->{'system_user'} );
    return Cpanel::FileUtils::Symlinks::remove_dangling_symlinks_in_dir( $self->{'maildir'}, { 'verbose' => $self->{'verbose'} } );
}

sub _unlink_conversion_in_progress {
    my ( $self, $success ) = @_;
    my $access_ids = Cpanel::AccessIds::ReducedPrivileges->new( $self->{'system_user'} );

    print "Removing conversion lock files for “$self->{'email_account'}”\n" if $self->{'verbose'};

    my $format_file = $self->_get_format_file_path();
    if ($success) {

        # Example: mailbox_format.cpanel
        Cpanel::FileUtils::Write::overwrite( $format_file, $self->{'target_format'}, 0644 );
    }
    else {
        Cpanel::FileUtils::Write::overwrite( $format_file, $self->{'source_format'}, 0644 );
    }

    # Example: conversion_in_progress.txt
    _unlink_or_warn( $self->{'_inprogress_file'} ) if $self->{'_inprogress_file'};
    return 1;
}

sub _get_format_file_path {
    my ($self) = @_;
    return "$self->{'maildir'}/mailbox_format.cpanel";
}

sub _get_inprogress_file_path {
    my ($self) = @_;
    return "$self->{'maildir'}/conversion_in_progress.txt";
}

sub _create_conversion_in_progress_if_disk_ok {
    my ($self) = @_;

    my $access_ids = Cpanel::AccessIds::ReducedPrivileges->new( $self->{'system_user'} );

    $self->_disk_space_check();

    print "Creating conversion lock file for “$self->{'email_account'}”\n" if $self->{'verbose'};
    my $msg = "This mailbox is being converted to $self->{'target_format'}.\nPID: $$";

    $self->{'_inprogress_file'} = $self->_get_inprogress_file_path();

    my $overwrite = $self->_should_overwrite_inprogress_file();

    # Example: conversion_in_progress.txt
    Cpanel::FileUtils::Write->can( $overwrite ? 'overwrite' : 'write' )->( $self->{'_inprogress_file'}, $msg, 0644 );

    # Example: mailbox_format.cpanel
    my $format_file = $self->_get_format_file_path();
    Cpanel::FileUtils::Write::overwrite( $format_file, $self->{'source_format'}, 0644 );

    return 1;
}

sub _should_overwrite_inprogress_file {
    my ($self) = @_;

    my $contents = Cpanel::LoadFile::load_if_exists( $self->{'_inprogress_file'} );

    if ($contents) {
        if ( $contents =~ m{PID:\s*([0-9]+)} ) {
            return 1 if !$self->_pid_is_alive($1);
        }
        else {
            # If there is not pid in the file
            # is still running
            return 1;
        }
    }

    # Does not exist is not safe to overwrite
    # since it could be created by another admin
    # and we do not want to try to convert at
    # the same time
    return 0;
}

sub _pid_is_alive {
    my ( $self, $active_pid ) = @_;

    if ( $active_pid > $MAX_PID ) {
        die "An invalid pid “$active_pid” was passed to _pid_is_alive";
    }
    return kill( 0, $active_pid ) ? 1 : 0;
}

sub _remove_mdbox_files {
    my ($self) = @_;

    return                                                                                 if $self->{'skip_removal'};
    print "Removing mdbox files for “$self->{'email_account'}” from $self->{'maildir'}.\n" if $self->{'verbose'};

    return Cpanel::Email::Mdbox::Utils::purge_mdbox(
        'user'    => $self->{'system_user'},
        'maildir' => $self->{'maildir'},
        'verbose' => $self->{'verbose'}
    );
}

sub _remove_maildir_files {
    my ($self) = @_;

    return                                                                                   if $self->{'skip_removal'};
    print "Removing maildir files for “$self->{'email_account'}” from $self->{'maildir'}.\n" if $self->{'verbose'};

    return Cpanel::Email::Maildir::Utils::purge_maildir(
        'user'    => $self->{'system_user'},
        'maildir' => $self->{'maildir'},
        'verbose' => $self->{'verbose'}
    );
}

sub _remove_files_for_mailbox_format {
    my ( $self, $format ) = @_;

    die "_remove_files_for_mailbox_format requires a value for format." if !length $format;

    if ( $format eq 'maildir' ) {
        return $self->_remove_maildir_files();
    }
    elsif ( $format eq 'mdbox' ) {
        return $self->_remove_mdbox_files();
    }
    die "This system does not know how to remove $format";

}

sub _dsync_until_status_zero {
    my ( $self, $disable_fsync ) = @_;

    die "_dsync_until_status_zero requires a value for disable_fsync." if !length $disable_fsync;

    return Cpanel::Dovecot::Sync::dsync_until_status_zero(
        'source_format'  => $self->{'source_format'},
        'target_format'  => $self->{'target_format'},
        'source_maildir' => $self->{'maildir'},
        'target_maildir' => $self->{'maildir'},
        'email_account'  => $self->{'email_account'},

        # CPANEL-28981: If the source has folders with native UTF-8 names,
        # then we need to specify this to dsync.
        #
        # FIXME: If a user has a mix of mUTF-7 and UTF-8, this will cause
        # havoc. However, should this occur, the seeds of failure were already
        # sewn when that was allowed to occur.
        'source_options' => $self->{'is_utf8'} ? ['UTF-8'] : [],
        'target_options' => $self->{'is_utf8'} ? ['UTF-8'] : [],

        # We must do a mirror operation as this will allow us to recover
        # from a failed conversion since even if we partially convert from
        # maildir to mdbox and then try to convert back from mdbox to maildir
        # the mirror operation will sync the change both directions.
        'sync_type'     => 'mirror',
        'disable_fsync' => $disable_fsync,
        'verbose'       => $self->{'verbose'},
    );
}

sub _disk_space_check {
    my ($self) = @_;

    # Note: 'email_account' has already been verified to exist in new
    # so its safe to just split() it here
    my $disk_used_bytes = Cpanel::Email::DiskUsage::get_disk_used( ( split( m{@}, $self->{'email_account'}, 2 ) )[ 0, 1 ] );
    my $disk_output     = '';
    my ( $disk_ok, $disk_msg ) = Cpanel::DiskCheck::target_has_enough_free_space_to_fit_source_sizes(
        'source_sizes'   => [ { 'mailbox' => $disk_used_bytes } ],
        'target'         => $self->{'maildir'},
        'output_coderef' => sub { my ($msg) = @_; $disk_output .= $msg; return 1; }
    );

    print "$disk_output\n" if $self->{'verbose'};

    die $disk_msg if !$disk_ok;

    return 1;
}

#----------------------------------------------------------------------

sub _unlink_or_warn {
    my ($path) = @_;

    unlink $path or do {
        warn "unlink($path): $!" if !$!{'ENOENT'};
    };

    return;
}

1;
