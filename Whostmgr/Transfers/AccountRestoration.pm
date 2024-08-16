package Whostmgr::Transfers::AccountRestoration;

# cpanel - Whostmgr/Transfers/AccountRestoration.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

# RR Audit: JNK

use Cpanel::Imports;

use Cpanel::Signals                   ();
use Cpanel::ConfigFiles               ();
use Cpanel::CachedDataStore           ();
use Cpanel::Locale                    ();
use Cpanel::LoadModule                ();
use Cpanel::LoadModule::Name          ();
use Cpanel::Carp                      ();
use Cpanel::Config::HasCpUserFile     ();
use Cpanel::ArrayFunc::Uniq           ();
use Cpanel::Logger                    ();
use Cpanel::Rlimit                    ();
use Cpanel::App                       ();
use Cpanel::Exception                 ();
use Cpanel::Server::Type              ();
use Cpanel::Server::Type::BuildNumber ();
use Cpanel::Logger                    ();

use Try::Tiny;

use Whostmgr::Transfers::Utils             ();
use Whostmgr::Transfers::ArchiveManager    ();
use Whostmgr::Transfers::RestrictedRestore ();
use Whostmgr::Transfers::Session::Config   ();

our $DEFAULT_RELATIVE_TIME = 1;
our $DEFAULT_PREREQ        = ['Domains'];
our $DEFAULT_PHASE         = 50;

my $logger = Cpanel::Logger->new();

my $locale;

sub new {
    my ( $class, %OPTS ) = @_;

    if ( defined $OPTS{'unrestricted_restore'} && ( $OPTS{'unrestricted_restore'} != $Whostmgr::Transfers::Session::Config::UNRESTRICTED && $OPTS{'unrestricted_restore'} != $Whostmgr::Transfers::Session::Config::RESTRICTED ) ) {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a valid value of “[_2]”.', [ $OPTS{'unrestricted_restore'}, 'unrestricted_restore' ] );
    }

    if ( !Whostmgr::Transfers::RestrictedRestore::available() && $OPTS{'unrestricted_restore'} == $Whostmgr::Transfers::Session::Config::RESTRICTED ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'Restricted Restore is not available in this version of [output,asis,cPanel].' );
    }

    my $unrestricted_restore = ( $OPTS{'unrestricted_restore'} && $OPTS{'unrestricted_restore'} == $Whostmgr::Transfers::Session::Config::UNRESTRICTED ) ? 1 : 0;

    my $utils = Whostmgr::Transfers::Utils->new(
        'unrestricted_restore' => $unrestricted_restore,
        'flags'                => $OPTS{'flags'},
        'output_obj'           => $OPTS{'output_obj'}
    );

    local $@;
    my $archive_manager = eval { Whostmgr::Transfers::ArchiveManager->new( 'utils' => $utils ) };

    if ( !$archive_manager ) {
        $logger->warn("Could not load ArchiveManager: $@");
        die "Could not load ArchiveManager: $@";
    }

    my $self = bless {
        '_pid'                  => $$,
        'path'                  => ( $OPTS{'path'}               || undef ),
        'flags'                 => ( $OPTS{'flags'}              || {} ),
        'percentage_coderef'    => ( $OPTS{'percentage_coderef'} || undef ),
        '_utils'                => $utils,
        '_archive_manager'      => $archive_manager,
        'disabled'              => $OPTS{'disabled'} || {},
        'loaded_custom_modules' => {},

    }, $class;

    $self->{'_utils'}->set_archive_manager( $self->{'_archive_manager'} );

    return $self;
}

sub restore_package {
    my ($self) = @_;

    Cpanel::Rlimit::set_rlimit_to_infinity();    # No memory limit for restores

    local $@;
    my ( $status, $statusmsg ) = eval { $self->_restore_package(); };

    $self->{'_archive_manager'}->cleanup();

    delete $self->{'Systems'};                   # TP TASK 20767: Destory all the system
                                                 # to ensure everything
                                                 # gets disconnected before global
                                                 # destruction

    #To ease debugging...
    delete $self->{'_utils'}{'locale'};

    if ($@) {
        return ( 0, $@ );
    }

    return ( $status, $statusmsg );
}

sub get_warnings {
    my ($self) = @_;
    return $self->{'_utils'}->get_warnings();
}

sub get_skipped_items {
    my ($self) = @_;
    return $self->{'_utils'}->get_skipped_items();
}

sub get_dangerous_items {
    my ($self) = @_;
    return $self->{'_utils'}->get_dangerous_items();
}

sub get_altered_items {
    my ($self) = @_;
    return $self->{'_utils'}->get_altered_items();
}

sub get_module_summaries {
    my ($self) = @_;

    my @summaries;
    my $restore_call = $self->generate_restore_execution_path();
    foreach my $module ( sort keys %{ $self->{'Systems'} } ) {
        my $summary              = $self->{'Systems'}->{$module}->get_summary();
        my $restricted_available = $self->{'Systems'}->{$module}->get_restricted_available();
        my $restricted_summary   = $self->{'Systems'}->{$module}->get_restricted_summary();
        my $notes                = $self->{'Systems'}->{$module}->get_notes();

        my %SUMMARY = (
            'module'               => $module,
            'summary'              => $summary,
            'restricted_available' => $restricted_available,
        );
        if ( $restricted_summary && @{$restricted_summary} ) {
            $SUMMARY{'restricted_summary'} = $restricted_summary;
        }
        if ( $notes && @{$notes} ) {
            $SUMMARY{'notes'} = $notes;
        }
        push @summaries, \%SUMMARY;
    }
    return \@summaries;

}

sub generate_restore_execution_path {
    my ($self) = @_;

    my $restore_call = {
        'completed'      => {},
        'todo'           => {},
        'relative_time'  => {},
        'all_time_units' => 0,
    };

    my @modules = $self->_get_all_restore_system_modules();

    foreach my $system (@modules) {
        my $is_fully_disabled = $self->{'disabled'}{$system} && $self->{'disabled'}{$system}{'all'};

        # It is not always safe to have the Account module fully disabled.
        # If the target account does not exist we must create the account during the transfer.
        if ( $is_fully_disabled && $system eq 'Account' && !( $self->{'_utils'}->pwnam() )[2] ) {
            delete $self->{'disabled'}{'Account'};
            $self->{'_utils'}->{'flags'}{'createacct'} = 1;
            $is_fully_disabled = 0;
        }

        next if $is_fully_disabled;

        my ( $ok, $obj ) = $self->_ensure_system_module_object($system);
        if ( !$ok ) {
            $self->warn($obj);    # obj will have the error
            next;
        }

        my $phase  = $obj->get_phase();
        my $prereq = $obj->get_prereq();
        my $time   = $obj->get_relative_time();

        $restore_call->{'all_time_units'} += $time;
        $restore_call->{'relative_time'}{$system} = $time;
        $restore_call->{'todo'}{$phase}{$system} = $prereq;
    }

    return $restore_call;
}

#Only used in testing.
sub call_one_restore_module {
    my ( $self, $system ) = @_;

    my ( $ok, $msg ) = $self->_ensure_archive_is_prepared_for_restore();
    if ( !$ok ) {
        return ( $ok, $msg );
    }

    return $self->_call_one_restore_module_without_archive_prep_check($system);
}

sub _call_one_restore_module_without_archive_prep_check {
    my ( $self, $system ) = @_;

    # Change validation modules to behave like whostmgr for unrestricted mode, and cpanel for restricted mode.
    local $Cpanel::App::appname = $self->{'_utils'}->is_unrestricted_restore() ? 'whostmgr' : 'cpanel';

    my ( $ok, $obj );
    ( $ok, $obj ) = $self->_ensure_system_module_object($system);

    if ( !$ok ) {
        return $obj;
    }

    my ( $disabled_ok, $disabled_msg ) = $self->_handle_disabled_flags($system);
    if ( $disabled_ok != 1 ) {
        return ( $disabled_ok, $disabled_msg );
    }

    my $opts_hr = $self->{'flags'};

    my $minver;

    if ( $opts_hr->{'restore_type'} ) {
        if ( $opts_hr->{'restore_type'} eq 'user' ) {
            $minver = $obj->minimum_transfer_source_version_for_user();
        }
        elsif ( $opts_hr->{'restore_type'} eq 'root' ) {
            $minver = $obj->minimum_transfer_source_version();
        }
    }

    if ($minver) {

        my $remote_cpversion = $opts_hr->{'remote_cpversion'};

        # Decrement so that we accept development versions.
        $minver--;

        require Cpanel::Version::Compare;

        if ( !$remote_cpversion || Cpanel::Version::Compare::compare( $remote_cpversion, '<', "11.$minver" ) ) {
            my $minver_pretty = '11.' . ( 1 + $minver );

            $self->{'_utils'}->out( locale()->maketext( 'The source server ([_1]) runs [asis,cPanel amp() WHM] version [_2], but this module requires version [_3] or higher.', $opts_hr->{'remote_host'}, $remote_cpversion, $minver_pretty ) );

            return 1;
        }
    }

    my $err;
    my @ret;
    try {
        @ret = $self->{'Systems'}->{$system}->restore();
    }
    catch {
        $err = $_;
    };

    if ($err) {
        shift @ret if @ret;

        my $err_as_text;

        # If the module does not trap its exceptions
        # we produce a backtrace as all modules are required
        # to trap their exceptions.  This will help the user report
        # a problem when something goes wrong.
        if ( UNIVERSAL::isa( $err, 'Cpanel::Exception' ) ) {
            $err_as_text = Cpanel::Exception::get_string($err) . "\n" . $err->longmess();
        }
        else {
            $err_as_text = Cpanel::Exception::get_string($err);
        }
        return ( 0, $err_as_text, @ret, $err );
    }

    if ( $self->{'Systems'}->{$system}->can('cleanup') ) {
        try {
            $self->{'Systems'}->{$system}->cleanup();
        }
        catch {
            my $err_as_text = Cpanel::Exception::get_string($_);
            $self->warn( _locale()->maketext( "Failed to cleanup restore system module “[_1]”: [_2]", $system, $err_as_text ) );
        };
    }

    return @ret;
}

sub _handle_disabled_flags {
    my ( $self, $system ) = @_;

    if ( $system eq 'Account' && $self->{'disabled'}{'Account'} && $self->{'disabled'}{'Account'}{'all'} ) {
        if ( !( $self->{'_utils'}->pwnam() )[2] ) {    # [2] is UID
            return ( 0, _locale()->maketext( "The restore has failed because the “[_1]” restore module has been skipped by request and the account “[_2]” does not already exist.", $system, $self->{'_utils'}->local_username() ) );
        }
        elsif ( !Cpanel::Config::HasCpUserFile::has_cpuser_file( $self->{'_utils'}->local_username() ) ) {
            return ( 0, _locale()->maketext( "The restore failed because the username “[_1]” is invalid or not an existing [asis,cPanel] user.", $self->{'_utils'}->local_username() ) );

        }
    }

    if ( $self->{'disabled'}{$system} ) {
        my $options_that_can_be_disabled = $self->{'Systems'}->{$system}->can('disable_options') ? $self->{'Systems'}->{$system}->disable_options() : [];

        foreach my $disabled_option ( keys %{ $self->{'disabled'}{$system} } ) {
            next if ( $disabled_option eq 'all' );
            if ( !grep { $_ eq $disabled_option } @{$options_that_can_be_disabled} ) {
                return ( 0, _locale()->maketext( "The “[_1]” option cannot be disabled in the “[_2]” restore module as requested.", $disabled_option, $system ) );
            }
        }

        if ( $self->{'disabled'}{$system}{'all'} ) {
            return ( 2, _locale()->maketext( "The “[_1]” restore module has been skipped because it was disabled by request.", $system ) );
        }
    }

    return ( 1, 'ok' );
}

sub _ensure_archive_is_prepared_for_restore {
    my ($self) = @_;

    my ( $message, $status );

    if ( !$self->{'_archive_manager'}->extracted() ) {

        #FIXME: this should be prepare cpmove for restore (could be incremental)
        ( $status, $message ) = $self->{'_archive_manager'}->safely_prepare_package_for_restore( $self->{'path'} );
        return ( 0, _locale()->maketext( "Failed to extract the archive at “[_1]”: [_2]", $self->{'path'}, $message ) ) if !$status;
    }

    my ( $err, $cpuser_data );
    try {
        $cpuser_data = $self->{'_utils'}->get_cpuser_data();
    }
    catch {
        $err = $_;
    };

    if ($err) {
        return ( 0, Cpanel::Exception::get_string($err) );
    }

    $message ||= _locale()->maketext("The system successfully prepared the archive for restoration.");

    return ( 1, $message );
}

sub _ensure_system_module_object {
    my ( $self, $module ) = @_;

    #Do this rather than checking %INC because some tests use custom packages.
    if ( !"Whostmgr::Transfers::Systems::$module"->can('new') ) {
        local @INC = ( $Whostmgr::Transfers::Session::Config::CUSTOM_PERL_MODULES_DIR, @INC );

        local $@;
        eval { Cpanel::LoadModule::load_perl_module("Whostmgr::Transfers::Systems::$module") } or do {
            delete $INC{"Whostmgr/Transfers/Systems/$module.pm"};
            return ( 0, "Failed to load restore module “$module”: $@" );
        };
        $self->{'loaded_custom_modules'}->{$module}++
          if $INC{"Whostmgr/Transfers/Systems/$module.pm"} =~ m/^\Q$Whostmgr::Transfers::Session::Config::CUSTOM_PERL_MODULES_DIR\E/;
    }

    my $err;
    try {
        $self->{'Systems'}->{$module} = "Whostmgr::Transfers::Systems::$module"->new( 'utils' => $self->{'_utils'}, 'archive_manager' => $self->{'_archive_manager'}, 'disabled' => $self->{'disabled'} );
    }
    catch {
        $err = $_;
    };

    if ($err) {
        my $err_as_text = Cpanel::Exception::get_string($err);
        $self->warn( _locale()->maketext( "Failed to create restore system module “[_1]”: [_2]", $module, $err_as_text ) );
        return ( 0, $err_as_text );
    }
    else {

        return ( 1, $self->{'Systems'}->{$module} );
    }
}

sub _fetch_modules_from_dir_or_die {
    my ( $self, $dir ) = @_;
    my @modules = $self->_fetch_modules_from_dir($dir);
    if ( !@modules ) {

        # This should never happen.  This function only exists as a safety
        # to prevent regressions.
        die "The system failed to find any modules in the directory “$dir”.";
    }
    return @modules;
}

sub _fetch_modules_from_dir {
    my ( $self, $dir ) = @_;

    $dir .= $Whostmgr::Transfers::Session::Config::MODULES_DIR;

    return Cpanel::LoadModule::Name::get_module_names_from_directory($dir);
}

sub _get_all_restore_system_modules {
    my ($self) = @_;

    # Sorted so random order problems don't bite us
    my @module_list = sort( Cpanel::ArrayFunc::Uniq::uniq(
            $self->_fetch_modules_from_dir($Whostmgr::Transfers::Session::Config::CUSTOM_PERL_MODULES_DIR),
            $self->_fetch_modules_from_dir_or_die($Cpanel::ConfigFiles::CPANEL_ROOT),
    ) );

    return @module_list;
}

sub _restore_package {
    my ($self) = @_;

    my $restore_call = $self->generate_restore_execution_path();

    foreach my $module ( keys %{ $self->{'disabled'} } ) {
        $self->{'_utils'}->out(
            _locale()->maketext(
                "The “[_1]” restore module has the following areas disabled by request: [list_and_quoted,_2]",
                $module,
                [ keys %{ $self->{'disabled'}{$module} } ]
              )
              . "\n"
        );
    }

    my ( $ok, $msg ) = $self->_run_archivemanager_extraction();
    return ( $ok, $msg ) if !$ok;

    if ( !Cpanel::Logger::is_sandbox() ) {

        my ( $cpuser_data, $skipped ) = $self->{'_utils'}->get_cpuser_data();

        my $created_in_version = $cpuser_data->{'CREATED_IN_VERSION'};

        my $current_build_is_cpanel    = Cpanel::Server::Type::BuildNumber::is_current_build_cpanel();
        my $created_is_same_as_current = Cpanel::Server::Type::BuildNumber::is_build_same_as_current_product($created_in_version);

        # CREATED_IN_VERSION was added in v94, so if it's missing it's safe to assume that the account
        # is being transferred from a cPanel machine
        if ( ( !length $created_in_version && !$current_build_is_cpanel ) || ( length $created_in_version && !$created_is_same_as_current ) ) {

            my $local  = Cpanel::Server::Type::BuildNumber::get_display_string_for_build_number($Cpanel::Version::Tiny::VERSION_BUILD);
            my $remote = Cpanel::Server::Type::BuildNumber::get_display_string_for_build_number($created_in_version) || "cPanel";

            $self->{'_utils'}->warn(
                _locale()->maketext(
                    "The “[_1]” account is not eligible for restoration on this server: “[_2]” accounts cannot be restored on “[_3]” systems.",
                    $cpuser_data->{'USER'},
                    $remote,
                    $local,
                  )
                  . "\n"
            );

            return ( 0, 'Aborted.' );
        }

    }

    return $self->_run_restore_modules($restore_call);
}

sub _run_archivemanager_extraction {
    my ($self) = @_;
    my $system = 'ArchiveManager';
    $self->{'_utils'}->start_module($system);
    $self->{'_utils'}->start_action( _locale()->maketext('Preparing archive for restoration …') );
    my ( $ok, $msg ) = $self->_ensure_archive_is_prepared_for_restore();
    $self->{'_utils'}->end_action();
    $self->{'_utils'}->end_module();
    $self->{'_utils'}->new_message( 'modulestatus', { 'module' => $system, 'status' => $ok, 'statusmsg' => $msg, 'output' => $msg } );

    return ( $ok, $msg );
}

sub _run_restore_modules {
    my ( $self, $restore_call ) = @_;

    $restore_call->{'completed_time_units'} = 0;

    foreach my $phase ( sort { $a <=> $b } keys %{ $restore_call->{'todo'} } ) {
        my $phase_todo = $restore_call->{'todo'}->{$phase};
        while ( scalar keys %{$phase_todo} ) {

            my $restored_at_least_one = 0;

            my %prereqs;

            # Restore modules in each phase are sorted here so that restore behavior is consistent, not used as a dependency ordering mechanism.
            # Change a restore module's prereq or phase if it needs to run before or after another restore module.
            foreach my $system ( sort keys %{$phase_todo} ) {
                $prereqs{$system} = [ @{ $phase_todo->{$system} } ];

                # If a module is disable we must ignore it as a prereq and hope for the best
                # for example: If we do
                #
                # /scripts/restorepkg --disable Domains /home/cpmove-myssltes.tar.gz
                #
                # we still want SSL to be restored even if Domains has been disabled.  The
                # use case for this is to only restore parts of an archive in the event
                # that we need to restore from backup because someone deleted/lost ssl
                # keys etc.
                if ( !values( @{ $prereqs{$system} } ) || !( grep { !$restore_call->{'completed'}->{$_} && !$self->{'disabled'}{$_} } @{ $prereqs{$system} } ) ) {
                    $restored_at_least_one = 1;

                    $restore_call->{'current_system'} = $system;
                    if ( $phase > 10 ) {
                        #
                        # We cannot abort until after the Account restore
                        # phase in order to avoid leaving cruft behind.
                        #
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
                            return ( 0, "Skipped." );
                        }
                    }

                    my ( $ok, $msg ) = $self->_run_restore_system_module( $restore_call, $phase_todo );

                    if ( !$ok ) {

                        # If the module failed we check to see if
                        # it was because we were aborting or skipping
                        # in the middle of it
                        if ( Cpanel::Signals::has_signal('TERM') ) {
                            return ( 0, 'Aborted: ' . $msg );
                        }
                        elsif ( Cpanel::Signals::has_signal('USR1') ) {
                            return ( 0, 'Skipped: ' . $msg );
                        }
                    }

                    return ( $ok, $msg ) if !$ok;
                }
            }

            if ( !$restored_at_least_one ) {
                my $msg = "Recursive dependencies in restore system phase “$phase” modules:\n" . join( "\n", map { "$_ => " . join( ", ", @{ $prereqs{$_} } ) } sort keys %{$phase_todo} ) . "\nCompleted: " . join( ', ', sort keys %{ $restore_call->{'completed'} } );
                $self->{'_utils'}->warn($msg);
                die $msg;
            }
        }
    }

    return ( 1, 'Account Restored' );
}

sub _run_restore_system_module {
    my ( $self, $restore_call, $phase_todo ) = @_;

    my $system = $restore_call->{'current_system'};
    my ( $status, $statusmsg, $output ) = $self->_call_one_restore_module_with_notices($system);

    my $statusmsg_as_text = $statusmsg;
    $self->{'_utils'}->new_message( 'modulestatus', { 'module' => $system, 'status' => $status, 'statusmsg' => $statusmsg_as_text, 'output' => $output } );

    $restore_call->{'completed_time_units'} += $restore_call->{'relative_time'}{$system};
    my $pct = int( ( $restore_call->{'completed_time_units'} / $restore_call->{'all_time_units'} ) * 100 );
    $self->{'percentage_coderef'}->($pct) if $self->{'percentage_coderef'};

    if ( !$status ) {
        $self->{'_utils'}->add_skipped_item( _locale()->maketext( "The “[_1]” restore module failed because of an error: [_2]", $system, $statusmsg_as_text ) );
        return ( 0, "$system failure: $statusmsg_as_text" ) if $self->{'Systems'}->{$system}->failure_is_fatal();
    }

    $restore_call->{'completed'}->{$system} = 1;

    delete $self->{'Systems'}->{$system};
    delete $phase_todo->{$system};

    return ( 1, 'ok' );
}

#Same as use_system_module_objectall_one_restore_module(), but with start/end notices.
sub _call_one_restore_module_with_notices {
    my ( $self, $system ) = @_;

    $self->{'_utils'}->start_module( $system, exists $self->{'loaded_custom_modules'}->{$system} ? 1 : 0 );

    my @ret = $self->_call_one_restore_module_without_archive_prep_check($system);

    #IMPORTANT!! This prevents memory usage overflows.
    Cpanel::CachedDataStore::clear_cache();

    $self->{'_utils'}->end_module();

    return @ret;
}

sub warn {
    my ( $self, @msg ) = @_;

    return $self->{'_utils'}->warn(@msg);
}

sub _locale {
    return $locale ||= Cpanel::Locale->get_handle();
}

1;
