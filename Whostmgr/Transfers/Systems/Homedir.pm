package Whostmgr::Transfers::Systems::Homedir;

# cpanel - Whostmgr/Transfers/Systems/Homedir.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

# RR Audit: JNK

use Cwd ();

use Cpanel::Signals                                 ();
use Cpanel::PwCache::Group                          ();
use Cpanel::ChildErrorStringifier                   ();
use Cpanel::Exception                               ();
use Cpanel::FileUtils::Dir                          ();
use Cpanel::SafetyBits::Chown                       ();
use Cpanel::Locale                                  ();
use Cpanel::SafeSync::UserDir                       ();
use Cpanel::SysAccounts                             ();
use Cpanel::Path::Dir                               ();
use Whostmgr::XferClient                            ();
use Whostmgr::Transfers::ArchiveManager::Subdomains ();

use constant _STREAM_EXCLUSIONS => ();

use Try::Tiny;

our $MAX_HOMEDIR_STREAM_ATTEMPTS = 5;

use parent qw(
  Whostmgr::Transfers::Systems
  Whostmgr::Transfers::SystemsBase::Frontpage
);

#NOTE: The *.* ensures that we don't exclude "webdav".
my @NON_MAIL_EXCLUDES = qw(
  ./etc/*.*/passwd*
  ./etc/*.*/quota*
  ./etc/*.*/shadow*
  ./mail/*
);

sub failure_is_fatal {
    return 1;
}

sub get_relative_time {
    return 8;
}

sub get_phase {
    return 10;
}

sub get_prereq {
    return [ 'Account', 'CpUser' ];
}

sub get_summary {
    my ($self) = @_;
    return [ $self->_locale()->maketext('This restores the home directory’s contents.') ];
}

sub get_restricted_available {
    return 1;
}

sub get_restricted_summary {
    my ($self) = @_;
    return [ $self->_locale()->maketext('If the home directory does not already exist, the system will not create it.') ];
}

*unrestricted_restore = \&restricted_restore;

sub restricted_restore {    ## no critic(Subroutines::ProhibitExcessComplexity)  -- Refactoring this function is a project, not a bug fix
    my ($self) = @_;

    my $olduser = $self->{'_utils'}->original_username();
    my $newuser = $self->{'_utils'}->local_username();

    my ( $uid, $gid, $user_homedir ) = ( $self->{'_utils'}->pwnam() )[ 2, 3, 7 ];
    my @supplemental_gids = Cpanel::PwCache::Group::get_supplemental_gids_for_user($newuser);

    my $trusted_archive_contents_dir  = $self->{'_archive_manager'}->trusted_archive_contents_dir();
    my $unsafe_to_read_source_homedir = $self->{'_archive_manager'}->unsafe_to_read_source_homedir();

    if ( !$user_homedir ) {
        $self->start_action('Transfer Error');
        return ( 0, $self->_locale()->maketext("Security violation: The home directory was not provided.") );
    }
    if ( $user_homedir eq "/" ) {
        $self->start_action('Transfer Error');
        return ( 0, $self->_locale()->maketext("Security violation: The home directory was set to “/”.") );
    }
    if ( !-d $user_homedir ) {
        if ( !$self->{'_utils'}->is_unrestricted_restore() ) {
            $self->start_action('Transfer Error');
            return ( 0, $self->_locale()->maketext( "Security violation… The home directory, “[_1]” does not exist and the system cannot create it in restricted mode.", $user_homedir ) );
        }

        # Try to recreate it as they may be restoring a backup
        elsif ( mkdir( $user_homedir, Cpanel::SysAccounts::homedir_perms() ) ) {
            if ( Cpanel::SafetyBits::Chown::safe_chown( $uid, $gid, $user_homedir ) ) {

                #safe (parent is owned by root)
            }
            else {
                return ( 0, $self->_locale()->maketext( "The system could not fix the ownership on the home directory at “[_1]”.", $user_homedir ) );
            }
        }
        else {
            $self->start_action('Transfer Error');
            return ( 0, $self->_locale()->maketext( "The system has encountered a security violation. The home directory, “[_1]”, does not exist, and the system could not create it due to an error: “[_2]”.", $user_homedir, "$!" ) );
        }
    }

    my $flags_hr = $self->{'_utils'}{'flags'};

    # The original streaming logic used this parameter and was WHM-only:
    my $old_whm_stream_config = $flags_hr->{'stream'};

    # This new parameter can accommodate WHM as well as cPanel:
    my $new_stream_config = $flags_hr->{'homedir_stream'};

    if ( $new_stream_config || $old_whm_stream_config ) {
        $self->start_action('Streaming home directory from source server …');

        if ( $self->disabled()->{'Mail'}{'all'} ) {
            return ( 0, $self->_locale()->maketext( "Disabling the “[_1]” module and home directory streaming are mutually exclusive options.", 'Mail' ) );

        }
        elsif ( $self->disabled()->{'Domains'}{'subdomains'} ) {
            return ( 0, $self->_locale()->maketext( "Disabling the subdomains in the “[_1]” module and home directory streaming are mutually exclusive options.", 'Domains' ) );
        }
    }
    else {
        $self->start_action('Restoring home directory …');
    }

    # manage exclude list

    my @excludes = $self->_STREAM_EXCLUSIONS();

    # This will be recreated by cpanellogd.
    push @excludes, './access-logs' if $olduser ne $newuser;

    # We do not need to transfer the LiteSpeed lscache
    push @excludes, '/lscache';

    if ( $self->disabled()->{'Domains'}{'subdomains'} ) {
        $self->_augment_excludes_with_subdomain_files( $user_homedir, \@excludes );
    }

    if ( $self->disabled()->{'Mail'}{'all'} ) {
        push @excludes, @NON_MAIL_EXCLUDES;
    }

    if ( $self->was_using_frontpage ) {
        $self->warn( $self->_locale()->maketext("The restoration process did not restore [asis,Microsoft® FrontPage®] files or directories because [asis,cPanel] has discontinued [asis,FrontPage] support.") );
        push @excludes, $self->frontpage_excludes();
    }

    # do the transfer
    if ($old_whm_stream_config) {
        my $streamok;
        my $attempts = $old_whm_stream_config->{'rsync'} ? ( $MAX_HOMEDIR_STREAM_ATTEMPTS * 2 ) : $MAX_HOMEDIR_STREAM_ATTEMPTS;
        for my $attempt ( 1 .. $attempts ) {

            # Fallback to generic streaming if rsync fails
            local $old_whm_stream_config->{'rsync'} = 0 if $attempt > $MAX_HOMEDIR_STREAM_ATTEMPTS;

            my $overwrite_with_delete = $self->{'_utils'}->{'flags'}->{'overwrite_with_delete'};

            # case 113733: Used only to download remote files
            $streamok = $self->whm_xferstream(
                $old_whm_stream_config,
                {
                    'user'                => $self->olduser(),
                    'target_dir'          => $user_homedir,
                    'uid'                 => $uid,
                    'gid'                 => $gid,
                    'supplemental_gids'   => \@supplemental_gids,
                    'excludes'            => \@excludes,
                    'preserve_hard_links' => 1,
                    'delete'              => $overwrite_with_delete,
                }
            );

            my ( $status, $statusmsg ) = _check_for_signals();
            return ( $status, $statusmsg ) if !$status;

            if ( !$streamok ) {
                $self->out("Trying again…\n");
            }
            else {
                last;
            }
        }
        if ( !$streamok ) {
            $self->_inform_of_stream_failure();
        }
    }
    elsif ($new_stream_config) {
        $self->_stream_new( $new_stream_config, \@excludes );
    }
    else {

        my $sync_source;
        my $has_files = 0;
        my $copy_err;

        if ( -e "$unsafe_to_read_source_homedir/homedir.tar" && -e $user_homedir ) {
            $sync_source = "$unsafe_to_read_source_homedir/homedir.tar";
            $has_files   = 1;
        }

        # Don't accidentally tar up the parent directory
        elsif ( -d "$unsafe_to_read_source_homedir/homedir" && !-l "$unsafe_to_read_source_homedir/homedir" ) {
            $sync_source = "$unsafe_to_read_source_homedir/homedir";

            try {
                $has_files = Cpanel::FileUtils::Dir::directory_has_nodes($sync_source);
            }
            catch {
                $copy_err = Cpanel::Exception::get_string($_);
            };
        }

        if ($has_files) {
            eval {    ##keep perltidy from wonking this up
                Cpanel::SafeSync::UserDir::sync_to_userdir(
                    'source'                => $sync_source,
                    'target'                => $user_homedir,
                    'setuid'                => [ $uid, $gid, @supplemental_gids ],
                    'exclude'               => \@excludes,
                    'anchored_excludes'     => 1,
                    'wildcards_match_slash' => 0,
                    'overwrite_public_html' => 1,
                );
            };

            if ($@) {
                $copy_err = $@;
            }
            elsif ($?) {
                my $err = Cpanel::ChildErrorStringifier->new($?);
                $copy_err = $err->autopsy();
            }
        }
        else {
            $self->warn( $self->_locale()->maketext('This account archive contains no home directory files to restore.') );
        }

        if ( length $copy_err ) {
            $self->warn($copy_err);
            home_dir_copy_message( $self->{'_utils'}, $newuser );
        }
    }

    my ( $status, $statusmsg ) = _check_for_signals();
    return ( $status, $statusmsg ) if !$status;

    if ( -e "$trusted_archive_contents_dir/httpfiles/files.tar" ) {
        Cpanel::SafeSync::UserDir::sync_to_userdir(
            'source' => "$trusted_archive_contents_dir/httpfiles/files.tar",
            'target' => $user_homedir,
            'setuid' => [ $uid, $gid, @supplemental_gids ]
        );
    }
    return ( 1, "Homedir restored" );
}

sub _stream_new ( $self, $new_stream_config, $excludes_ar ) {    ## no critic qw(ManyArgs) - mis-parse
    require Cpanel::Homedir::Stream;

    my $newuser      = $self->newuser();
    my $user_homedir = ( $self->utils()->pwnam() )[7];

    my @xtra_stream_args;

    # sanity check
    if ( $new_stream_config->{'application'} eq 'cpanel' ) {
        push @xtra_stream_args, (

            # Since we’re authenticating unprivileged,
            setuids => [$newuser],
        );
    }
    else {
        die "only cP supports new stream config for now";
    }

    my $max_attempts = $MAX_HOMEDIR_STREAM_ATTEMPTS * 2;

    my $ok;

    for my $n ( 1 .. $max_attempts ) {
        try {
            Cpanel::Homedir::Stream::rsync_from_cpanel(
                %{$new_stream_config}{
                    'api_token',
                    'api_token_username',
                    'host',
                },

                destination => $user_homedir,
                exclude     => $excludes_ar,

                tls_verification => 'off',

                @xtra_stream_args,
            );

            $ok = 1;
        }
        catch {
            $self->warn("Stream failed: $_");
        };

        last if $ok;

        if ( $max_attempts != $n ) {
            $self->out('Retrying …');
        }
    }

    if ( !$ok ) {
        $self->_inform_of_stream_failure();
    }

    return $ok;
}

## cpdev: stream of homedir complete
sub whm_xferstream {
    my ( $self, $hr_AUTHOPTS, $hr_OPTS ) = @_;

    my $err;
    my $streamok = 0;
    try {
        local $SIG{'__WARN__'} = sub {
            $self->warn( Cpanel::Exception::get_string(@_) );
        };
        if ( $hr_AUTHOPTS->{'rsync'} ) {
            $streamok = Whostmgr::XferClient::rsync( $hr_AUTHOPTS, $hr_OPTS );
        }
        else {
            $streamok = Whostmgr::XferClient::stream( $hr_AUTHOPTS, $hr_OPTS );
        }
    }
    catch {
        $err = $_;
    };

    if ($err) {
        $self->warn( Cpanel::Exception::get_string($err) );
    }

    return $streamok;
}

sub home_dir_copy_message {
    my ( $self, $user ) = @_;

    $self->warn("Unable to copy home directory for user: $user");

    return;
}

sub _augment_excludes_with_subdomain_files {
    my ( $self, $user_homedir, $exclude_ref ) = @_;
    my ( $sub_ok, $subdomains ) = Whostmgr::Transfers::ArchiveManager::Subdomains::retrieve_subdomains_from_extracted_archive( $self->archive_manager() );
    if ($sub_ok) {
        foreach my $subref ( @{$subdomains} ) {
            my $docroot       = $subref->{'docroot'};
            my $fullsubdomain = $subref->{'fullsubdomain'};
            if ( !Cpanel::Path::Dir::dir_is_the_same( $docroot, "$user_homedir/public_html" )
                && ( Cpanel::Path::Dir::dir_is_below( $docroot, $user_homedir ) || Cpanel::Path::Dir::dir_is_below( $docroot, "$user_homedir/public_html" ) ) ) {
                if ( my $normalized_relative_docroot = Cpanel::Path::Dir::relative_dir( $docroot, $user_homedir ) ) {
                    push @{$exclude_ref}, "./$normalized_relative_docroot", "./$normalized_relative_docroot/*";
                }
            }
            push @{$exclude_ref}, "./mail/$fullsubdomain", "./etc/$fullsubdomain", "./mail/$fullsubdomain/*", "./etc/$fullsubdomain/*";
        }
    }
    else {
        $self->warn( $self->_locale()->maketext( "Failed to retrieve subdomains from the archive: [_1]", $subdomains ) );
    }
    return;
}

sub _inform_of_stream_failure ($self) {
    my $newuser = $self->newuser();

    $self->warn("Streaming homedir from remote server failed. You will need to transfer it manually!!!");
    $self->home_dir_copy_message($newuser);

    return;
}

sub _check_for_signals {

    # Avoid Cpanel::Signals::signal_needs_to_be_handled  and use
    # Cpanel::Signals::has_signal as it does not clear the state.
    #
    # Since we are not handling the signal here we only
    # need to break out of the loop as the signal will
    # ultimately be handled in the transfer system at
    # a higher level.
    if ( Cpanel::Signals::has_signal('TERM') ) {
        return ( 0, 'Aborted.' );
    }
    elsif ( Cpanel::Signals::has_signal('USR1') ) {

        return ( 0, 'Skipped.' );
    }
    return 1;
}

1;
