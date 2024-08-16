package Whostmgr::Transfers::Systems::Mailman;

# cpanel - Whostmgr/Transfers/Systems/Mailman.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

# RR Audit: JNK, JTK

use Try::Tiny;

use Cpanel::AccessIds::ReducedPrivileges ();
use Cpanel::FileUtils::Dir               ();
use Cpanel::FileUtils::Write             ();
use Cpanel::SafeRun::Object              ();
use Cpanel::LoadFile                     ();
use Cpanel::SafeSync::UserDir            ();
use Cpanel::ConfigFiles                  ();
use Cpanel::TempFile                     ();
use Cpanel::Rand::Get                    ();
use Cpanel::Hostname                     ();
use Cpanel::Mailman::ListManager         ();
use Cpanel::Mailman::NameUtils           ();
use Cpanel::Archive::Utils               ();
use Cpanel::Validate::EmailLocalPart     ();
use Cpanel::Exception                    ();
use Cpanel::PwCache                      ();
use Cpanel::Fcntl::Constants             ();
use Cpanel::SafeDir::MK                  ();
use Cpanel::SafeFind                     ();
use Cpanel::Autodie                      ();
use Cpanel::FileUtils::Open              ();
use Cpanel::Mkdir                        ();

use parent qw(
  Whostmgr::Transfers::SystemsBase::Distributable::Mail
);

my %MAILMANLISTS = (
    'mm'  => 'lists',
    'mms' => 'suspended.lists'
);

# AKA "$CPANEL_ROOT/3rdparty/mailman";

my $ARCHIVES_SRCDIR  = 'priv';
my $ARCHIVES_DESTDIR = 'private';

sub get_summary {
    my ($self) = @_;
    return [ $self->_locale()->maketext('This restores mailing lists.') ];
}

sub get_restricted_available {
    return 1;
}

*restricted_restore = \&unrestricted_restore;

sub unrestricted_restore {
    my ($self) = @_;

    my ( $mailman_uid, $mailman_gid ) = ( Cpanel::PwCache::getpwnam($Cpanel::ConfigFiles::MAILMAN_USER) )[ 2, 3 ];

    $self->start_action('Restoring Mailman lists');
    my ( $list_restore_status, $restored_lists_ar ) = $self->_safe_restore_lists();

    if ( $list_restore_status && @{$restored_lists_ar} ) {
        $self->start_action('Restoring Mailman Raw Lists');
        $self->_restore_rawlists();    # For CIHost and others

        $self->start_action('Restoring Mailman Archives');
        $self->_restore_archives();

        $self->start_action('Resetting Mailman Hostnames');
        $self->_reset_hostnames();     # For Plesk and others

        # Now for everyone we imported we need to rebuild the config
        # This will also rebuild the symlinks if its a public list
        $self->start_action('Rebuilding Mailman Config and setting permissions');
        $self->_rebuild_and_fix_perms($restored_lists_ar);
    }

    return ( 1, "Mailman Restored" );
}

sub _is_valid_list {
    my ( $self, $list ) = @_;

    my ( $listname, $domain ) = Cpanel::Mailman::NameUtils::parse_name($list);

    return 0 if !$self->{'_utils'}->is_restorable_domain($domain);
    return 0 if !Cpanel::Validate::EmailLocalPart::is_valid($listname);

    return 1;
}

sub _sanitize_pickle_file {
    my ( $self, $pck_file ) = @_;

    my $original_perms      = ( stat($pck_file) )[2];
    my $user_we_restored_to = $self->{'_utils'}->local_username() || $Cpanel::ConfigFiles::MAILMAN_USER;
    my $run;
    my $saferun_error;
    try {
        $run = Cpanel::SafeRun::Object->new(
            program => '/usr/local/cpanel/bin/safe_dump_pickle',
            args    => [ $pck_file, $user_we_restored_to ],
        );
    }
    catch {
        $saferun_error = $_;
    };
    if ($saferun_error) {
        my $errstr = Cpanel::Exception::get_string($saferun_error);
        $self->warn( $self->_locale()->maketext( "The system failed to sanitize the pickle file “[_1]” because of an error: [_2]", $pck_file, $errstr ) );

        return 0;
    }
    elsif ( $run->CHILD_ERROR() ) {
        $self->warn( $self->_locale()->maketext( "The system failed to sanitize the pickle file “[_1]” because the child process terminated with the error code “[_2]”.", $pck_file, $run->error_code() ) );
        $self->warn( $run->stderr() );
        return 0;
    }

    my $sanitized_pck_output = $run->stdout();
    Cpanel::FileUtils::Write::overwrite_no_exceptions( $pck_file, $sanitized_pck_output, $original_perms & 00777 ) or do {
        $self->warn( $self->_locale()->maketext( "The system failed to write sanitized pickle data into the file “[_1]” because of an error: [_2]", $pck_file, $! ) );
        return 0;
    };

    return 1;
}

sub _get_lists_to_restore {
    my ($self) = @_;

    my $extractdir = $self->extractdir();
    my @lists_to_restore;

    foreach my $srcdir ( keys %MAILMANLISTS ) {
        next if ( !-e "$extractdir/$srcdir" );
        my $destdir = $MAILMANLISTS{$srcdir};

        local $@;
        my $has_nodes = eval { Cpanel::FileUtils::Dir::directory_has_nodes("$extractdir/$srcdir") };
        warn $@ if $@;

        if ($has_nodes) {
            local $@;
            my $node_ref = eval { Cpanel::FileUtils::Dir::get_directory_nodes("$extractdir/$srcdir") };
            warn $@ if $@;

            if ($node_ref) {
                foreach my $node ( @{$node_ref} ) {
                    if ( $self->_is_valid_list($node) ) {
                        push @lists_to_restore, { 'sourcedir' => "$extractdir/$srcdir/$node", 'name' => $node, 'destdir' => $destdir };
                    }
                    else {
                        $self->{'_utils'}->add_skipped_item("$node mailman list");
                    }
                }
            }
        }
    }
    return ( 1, \@lists_to_restore );
}

sub _safe_restore_lists {
    my ($self) = @_;

    #Queue up the restore actions so that we can validate everything first.
    my ( $get_lists_status, $lists_to_restore_ref ) = $self->_get_lists_to_restore();
    return ( 0, $lists_to_restore_ref ) if !$get_lists_status;

    my ( $mailman_uid, $mailman_gid ) = ( Cpanel::PwCache::getpwnam($Cpanel::ConfigFiles::MAILMAN_USER) )[ 2, 3 ];
    my $temp_obj        = Cpanel::TempFile->new();
    my $restore_tmp_dir = $temp_obj->dir();
    my @lists_restored;

    foreach my $list ( @{$lists_to_restore_ref} ) {
        my $sourcedir = $list->{'sourcedir'};
        my $listname  = $list->{'name'};
        my $destdir   = $list->{'destdir'};

        mkdir( "$restore_tmp_dir/$listname", 0700 );

        my $target      = "$restore_tmp_dir/$listname";
        my $sync_status = Cpanel::SafeSync::UserDir::sync_to_userdir(
            'source' => $sourcedir,
            'target' => $target,
        );

        if ( !$sync_status ) {
            $self->{'_utils'}->add_skipped_item("Failed to restore: $listname. Could not sync to: $restore_tmp_dir/$listname");
            next;
        }

        my ( $status, $statusmsg, $ret ) = Cpanel::Archive::Utils::sanitize_extraction_target($target);
        foreach my $unlinked ( @{ $ret->{'unlinked'} } ) {
            $self->{'_utils'}->add_skipped_item( $self->_locale()->maketext( 'Removed non-file, non-directory “[_1]”.', $unlinked ) );
        }
        foreach my $modified ( @{ $ret->{'modified'} } ) {
            $self->{'_utils'}->warn( $self->_locale()->maketext( 'Sanitized permission on “[_1]”.', $modified ) );
        }
        return ( $status, $statusmsg ) if !$status;

        $self->_sanitize_mailman_tree( $listname, "$restore_tmp_dir/$listname/" ) or next();

        my $mkdir_ok = Cpanel::AccessIds::ReducedPrivileges::call_as_user(
            sub {
                return Cpanel::SafeDir::MK::safemkdir( "$Cpanel::ConfigFiles::MAILMAN_ROOT/$destdir/$listname", 06775 );
            },
            $Cpanel::ConfigFiles::MAILMAN_USER,
        );

        if ( !$mkdir_ok ) {
            $self->{'_utils'}->add_skipped_item("Could not create list dir $Cpanel::ConfigFiles::MAILMAN_ROOT/$destdir/$listname: $!");
            next;
        }

        my $sync_ok = Cpanel::SafeSync::UserDir::sync_to_userdir(
            'source' => "$restore_tmp_dir/$listname",
            'target' => "$Cpanel::ConfigFiles::MAILMAN_ROOT/$destdir/$listname",
            'setuid' => [ $mailman_uid, $mailman_gid ]
        );

        if ($sync_ok) {
            push @lists_restored, $list;
        }
        else {
            $self->{'_utils'}->add_skipped_item("The system failed to restore: $listname. Could not sync as user mailman to: $Cpanel::ConfigFiles::MAILMAN_ROOT/$destdir");
        }
    }

    return ( 1, \@lists_restored );
}

sub _restore_rawlists {
    my ($self) = @_;

    my $extractdir = $self->extractdir();

    #TODO: Determine if this needs to be in here at all.
    ## FWIW: this seems to only be used by pkgacct-ciXost
    ## case 47390: word is, ciXost is not really supported anymore; consider this a dead block; IF AND
    ##   WHEN the "rawlists" directory of a cpmove archive is used again, the call to newlist should
    ##   probably be adjusted
    return if !( -d "$extractdir/rawlists" );

    my $user_we_restored_to = $self->newuser();
    my @domains             = $self->{'_utils'}->domains();
    my $domain              = $domains[0];
    my $hostname            = Cpanel::Hostname::gethostname();

    local $@;
    my $rawlists_ar = eval { Cpanel::FileUtils::Dir::get_directory_nodes("$extractdir/rawlists") };
    warn $@ if $@;

    my @lists_to_create;

    foreach my $rawlist (@$rawlists_ar) {
        my $full_name = Cpanel::Mailman::NameUtils::make_name( $rawlist, $domain );
        if ( !$self->_is_valid_list($full_name) ) {
            push @lists_to_create, { 'rawlist' => $rawlist, 'domain' => $domain };
        }
        else {
            $self->{'_utils'}->add_skipped_item("Could not restore invalid rawlist: $full_name");
        }
    }

    if (@lists_to_create) {
        foreach my $list (@$rawlists_ar) {
            my $rawlist = $list->{'rawlist'};
            my $domain  = $list->{'domain'};

            my $listfile = "$extractdir/rawlists/$rawlist";

            my ( $size_ok, $size_msg ) = $self->{'_utils'}->check_file_size( $listfile, ( 1024 * 1024 * 32 ) );
            return ( 0, $size_msg ) if !$size_ok;

            my ( $load_ok, $members_list_ref ) = Cpanel::LoadFile::loadfile_r($listfile);

            if ( !$load_ok ) {
                $self->{'_utils'}->add_skipped_item("list $rawlist: $members_list_ref");
                next;
            }

            my $randpass = Cpanel::Rand::Get::getranddata(16);
            $self->warn("!!!WARNING!!! Setting Password for Mailing list $rawlist to “$randpass”");
            my ( $err, $ret );
            try {
                $ret = Cpanel::Mailman::ListManager::create_list(
                    'list'    => $rawlist,
                    'domain'  => $domain,
                    'owner'   => $user_we_restored_to,
                    'pass'    => $randpass,
                    'members' => $members_list_ref,
                );
            }
            catch {
                $err = $_;
            };

            if ($err) {
                $self->warn( $self->_locale()->maketext( 'Failed to import list “[_1]” because of an error: [_2]', $rawlist, Cpanel::Exception::get_string($err) ) );
            }
            else {
                $self->out( $self->_locale()->maketext( 'Imported list “[_1]”.', $rawlist ) );
            }
        }
    }

    return 1;
}

sub _restore_archives {
    my ($self) = @_;

    my $extractdir = $self->extractdir();

    my ( $mailman_uid, $mailman_gid ) = ( Cpanel::PwCache::getpwnam($Cpanel::ConfigFiles::MAILMAN_USER) )[ 2, 3 ];
    my $archives_srcdir  = "$extractdir/mma/$ARCHIVES_SRCDIR";
    my $archives_destdir = "$Cpanel::ConfigFiles::MAILMAN_ROOT/archives/$ARCHIVES_DESTDIR";
    my $CHUNK_SIZE       = 2**16;

    if ( -d $archives_srcdir ) {
        local $@;
        my $archives_ar = eval { Cpanel::FileUtils::Dir::get_directory_nodes($archives_srcdir) };
        warn $@ if $@;

        # The archives are stored in a .mbox file which
        # gets restored by the mailman/bin/arch
        # tool
        my @mbox_dirs = grep { /\.mbox$/ } @$archives_ar;

        my @sanitized_restore_dirs = ();
        foreach my $dir (@mbox_dirs) {
            my $list = $dir =~ s{\.mbox$}{}r;
            if ( !$self->_is_valid_list($list) ) {
                $self->{'_utils'}->add_skipped_item("mailman archives for $list");
                next;
            }

            my $source_mbox_file = "$archives_srcdir/$dir/$dir";
            if ( !-e $source_mbox_file ) {

                # If there are no archives for the list, simply restore an empty
                # file so that archives work in the future.
                $source_mbox_file = '/dev/null';
            }

            my $target_dir       = "$archives_destdir/$dir";
            my $target_mbox_file = "$archives_destdir/$dir/$dir";

            try {
                Cpanel::Autodie::sysopen( my $mbox_file, $source_mbox_file, $Cpanel::Fcntl::Constants::O_RDONLY | $Cpanel::Fcntl::Constants::O_NOFOLLOW, 0600 );
                Cpanel::AccessIds::ReducedPrivileges::call_as_user(
                    sub {
                        Cpanel::Mkdir::ensure_directory_existence_and_mode( $target_dir, 0770 );
                        if ( Cpanel::FileUtils::Open::sysopen_with_real_perms( my $write_fh, $target_mbox_file, 'O_WRONLY|O_CREAT', 0660 ) ) {
                            my $buffer = '';
                            while ( Cpanel::Autodie::sysread_sigguard( $mbox_file, $buffer, $CHUNK_SIZE ) ) {
                                Cpanel::Autodie::syswrite_sigguard( $write_fh, $buffer );
                            }
                            $self->out( $self->_locale()->maketext( "Restored archive mbox file for the “[_1]” list.", $list ) );
                        }
                        else {
                            die $self->_locale()->maketext( "The system failed to write to “[_1]” because of an error: [_2].", $target_mbox_file, $! );
                        }

                    },
                    $Cpanel::ConfigFiles::MAILMAN_USER
                );
            }
            catch {
                my $err = Cpanel::Exception::get_string($_);
                $self->warn( $self->_locale()->maketext( "The system failed to restore the mailman archive for “[_1]” because of an error: [_2].", $list, $err ) );
                $self->{'_utils'}->add_skipped_item("Mailing list archive: $list");
            };

        }
    }

    return 1;
}

sub _reset_hostnames {
    my ($self) = @_;

    my $extractdir          = $self->extractdir();
    my $reset_hostname_file = "$extractdir/meta/mailman_reset_hostname";
    ## regenerates the hostname and archives for mailman lists coming from Plesk
    if ( -e $reset_hostname_file ) {

        my ( $size_ok, $size_msg ) = $self->{'_utils'}->check_file_size( $reset_hostname_file, ( 1024 * 1024 ) );
        return ( 0, $size_msg ) if !$size_ok;

        open( my $fh, '<', $reset_hostname_file ) or do {
            return ( 0, $self->_locale()->maketext( 'The system failed to open the file “[_1]” because of an error: [_2]', $reset_hostname_file, $! ) );
        };

        local $!;
        while ( my $line = readline $fh ) {
            chomp($line);
            my ( $listname, $domain ) = split( m{:\s*}, $line );
            my $full_name = Cpanel::Mailman::NameUtils::make_name( $listname, $domain );
            if ( !$self->_is_valid_list($full_name) ) {
                $self->{'_utils'}->add_skipped_item("Could not restore hostname of invalid mailman list: $full_name");
                next;
            }

            if ( !-e "$Cpanel::ConfigFiles::MAILMAN_ROOT/lists/$full_name" ) {
                $self->{'_utils'}->add_skipped_item("Could not restore hostname of missing mailman list: $full_name");
                next;
            }
        }

        if ($!) {

            #TODO: error handling
        }
    }

    return 1;
}

sub _rebuild_and_fix_perms {
    my ( $self, $lists_ref ) = @_;

    foreach my $listref ( @{$lists_ref} ) {
        my $list = $listref->{'name'};

        if ( $listref->{'destdir'} ne 'lists' ) {

            # do not work on suspended lists
            $self->{'_utils'}->add_skipped_item( $self->_locale()->maketext( "The system skipped the rebuild of the list “[_1]” because the account is suspended.", $list ) );
            next;
        }

        if ( !-e "$Cpanel::ConfigFiles::MAILMAN_ROOT/lists/$list" ) {
            $self->{'_utils'}->add_skipped_item( $self->_locale()->maketext( "The system skipped the rebuild of the list “[_1]” because it does not exist in “[_2]”.", $list, "$Cpanel::ConfigFiles::MAILMAN_ROOT/lists/$list" ) );
            next;
        }

        #FIXME: regenerate_list needs to be done in unsuspend

        $self->out( $self->_locale()->maketext( 'Rebuilding configuration and archives for the “[_1]” list.', $list ) );
        {
            local $SIG{'__WARN__'} = sub {
                $self->warn(@_);
            };
            Cpanel::Mailman::ListManager::regenerate_list($list);
        }
        $self->out( $self->_locale()->maketext( 'Restoring permissions for the “[_1]” list.', $list ) );
        Cpanel::Mailman::ListManager::fix_mailman_list_permissions( { 'list' => $list } );

    }

    return 1;

}

sub _sanitize_mailman_tree {
    my ( $self, $listname, $mmdir ) = @_;

    my $list_can_be_restored = 1;
    my ( $filename, $relative_filename );
    Cpanel::SafeFind::finddepth(
        {
            wanted => sub {
                return if $File::Find::name !~ m{^\Q$mmdir\E};
                $filename          = ( split( m{/}, $File::Find::name ) )[-1];
                $relative_filename = $File::Find::name;
                $relative_filename =~ s{^\Q$mmdir\E/?}{}g;

                if ( -l $File::Find::name ) {
                    my $link_target = readlink($File::Find::name);

                    my $file_extension = ( split( m{\.}, $filename ) )[-1];
                    my $link_extension = ( split( m{\.}, $link_target ) )[-1];

                    if ( !length $file_extension || !length $link_extension || $file_extension ne $link_extension ) {
                        unlink($File::Find::name) || do {
                            $self->{'_utils'}->add_dangerous_item("Skipped list: $listname could not be sanitized: $relative_filename");
                            $list_can_be_restored = 0;
                            return;
                        };
                        $self->{'_utils'}->add_skipped_item("Removed symlink that does not match to the same type: $relative_filename");
                        return;
                    }
                }

                if ( $File::Find::name =~ m/\.pck$/ ) {
                    $self->_sanitize_pickle_file($File::Find::name) || do {
                        unlink($File::Find::name) || do {
                            $self->{'_utils'}->add_dangerous_item("Skipped list: $listname could not be sanitized: $relative_filename");

                            $list_can_be_restored = 0;
                            return;
                        };
                        $self->{'_utils'}->add_dangerous_item("Removed pickle file that could not be sanitized: $relative_filename");
                        return;
                    };
                }
                elsif ( $File::Find::name =~ m/\.db$/ ) {
                    unlink($File::Find::name) || do {
                        $self->{'_utils'}->add_dangerous_item("Skipped list: $listname could not be sanitized: $relative_filename");
                        $list_can_be_restored = 0;
                        return;
                    };
                    $self->{'_utils'}->add_skipped_item("Removed marshal file: $relative_filename");
                    return;
                }
                elsif ( $File::Find::name =~ m{\.last$} ) {
                    unlink($File::Find::name) || do {
                        $self->{'_utils'}->add_dangerous_item("Skipped list: $listname could not be sanitized: $relative_filename");
                        $list_can_be_restored = 0;
                        return;
                    };
                    return;
                }
                elsif ( $File::Find::name =~ m{\.(?:txt|gz|mbox|html)$} ) {
                    return;
                }
                elsif ( ( $filename =~ tr{.}{} ) > 1 ) {
                    unlink($File::Find::name) || do {
                        $self->{'_utils'}->add_dangerous_item("Skipped list: $listname could not be sanitized: $relative_filename");
                        $list_can_be_restored = 0;
                        return;
                    };
                    $self->{'_utils'}->add_skipped_item("Removed mailman file with multiple periods: $relative_filename");
                    return;
                }
                elsif ( $File::Find::name =~ m{/database/[^/]+$} ) {
                    unlink($File::Find::name) || do {
                        $self->{'_utils'}->add_dangerous_item("Skipped list: $listname could not be sanitized: $relative_filename");
                        $list_can_be_restored = 0;
                        return;
                    };

                    # No sense in telling them this as we will tell them later if the regerate fails.
                    # $self->{'_utils'}->add_skipped_item("Discarding archive database as it will be regenerated later: $relative_filename");
                    return;
                }
                elsif ( !-d $File::Find::name ) {
                    unlink($File::Find::name) || do {
                        $self->{'_utils'}->add_dangerous_item("Skipped list: $listname could not be sanitized: $relative_filename");
                        $list_can_be_restored = 0;
                        return;
                    };

                    # case CPANEL-1865: Attachements will be restored via Cpanel::Mailman::ListManager::regenerate_list()
                    # so do not warn about them here.
                    if ( index( $relative_filename, 'attachments/' ) != 0 ) {
                        $self->{'_utils'}->add_skipped_item("Removed unknown mailman file: $relative_filename");
                    }
                    return;
                }
            },
            'no_chdir' => 1
        },
        $mmdir
    );

    return $list_can_be_restored;
}

1;
