package Cpanel::Backup::Queue;

# cpanel - Cpanel/Backup/Queue.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

{

    package Cpanel::Backup::Queue::transport_backup;
    use base 'Cpanel::TaskQueue::Processor';

    use Cpanel::Transport::Files           ();
    use Cpanel::Backup::Transport          ();
    use Cpanel::Backup::Transport::Session ();
    use Cpanel::JSON                       ();
    use Cpanel::FileUtils::Open            ();
    use Cpanel::BackupMount                ();
    use Cpanel::Logger::Serialized         ();
    use File::Spec                         ();
    use File::Path                         ();
    use File::Basename                     ();
    use File::Glob                         ();
    use Cpanel::Backup::Config             ();
    use Cpanel::Exception                  ();
    use Cpanel::Locale                     ();
    use Cpanel::Time::ISO                  ();
    use Cpanel::Backup::Transport::History ();
    use Try::Tiny;

    my $debug = 1;
    my $locale;

    sub process_task {
        my ( $self, $args, $logger ) = @_;

        $locale ||= Cpanel::Locale->get_handle();

        # The args could get spilt into multiple array entries if they contain a space
        if ( exists $args->{'_args'} && scalar( @{ $args->{'_args'} } ) ) {
            my $joined_args = join( ' ', @{ $args->{'_args'} } );
            $args = Cpanel::JSON::Load($joined_args);
        }

        my $backup_type                      = $args->{'type'};
        my $session_id                       = $args->{'session_id'};
        my $remote_path                      = $args->{'remote_path'};
        my $local_path                       = $args->{'local_path'};
        my $error_aggregator_file            = $args->{'error_aggregator_file'};
        my $serialized_error_aggregator_file = $args->{'serialized_error_aggregator_file'};
        my $user                             = $args->{'user'};

        #XXX theoretically this is the same day as the backup, supposing it doesn't take more than a day.
        # We only want YYYY-MM-DD (the first 10 chars), as this is the way we store the dirs for pruning
        my $date = substr( Cpanel::Time::ISO::unix2iso( $args->{time} ), 0, 10 );

        $backup_type //= '';

        # To delete the file 'keep_local' must be specified and set to false
        my $keeplocal = exists $args->{'keep_local'} ? $args->{'keep_local'} : 1;

        ################################################################################
        # Process special command arguments first that don't care about individual transports
        ################################################################################

        # If we have received the unmount command, then there is nothing else to do but it
        if ( $args->{'cmd'} eq 'unmount' ) {

            # This is the operation for unmounting the backup volume
            # We queue this after transfering the files so it doesn't get
            # unmounted when we are still trying to upload the backup files
            my $volume   = $args->{'volume'};
            my $mountkey = $args->{'mountkey'};

            if ( $volume and $mountkey ) {
                Cpanel::BackupMount::unmount_backup_disk( $volume, $mountkey );
            }
            else {
                $logger->warn("unmount operation queued without specifying the volume and mountkey");
            }

            # The unmount task does not involve the transports, we are done
            return;
        }
        elsif ( $args->{'cmd'} eq 'remove_system_backup_tar_file' ) {

            # This command is to remove the temporary system backup tar file
            # when we are done with it
            my $system_backup_tar = $args->{'local_path'};

            if ( -f $system_backup_tar ) {
                $logger->info("Deleting system backup tar file:  $system_backup_tar");
                unlink $system_backup_tar
                  or $logger->warn("Unable to delete $system_backup_tar");
            }
            else {
                $logger->warn("remove_system_backup_tar_file called with bogus file:  $system_backup_tar");
            }

            # Nothing to do after this
            return;
        }
        elsif ( $args->{'cmd'} eq 'report_any_errors' ) {

            # If the aggregator file doesn't exist or doesn't have content,
            # Then there are no errors to report
            return unless ( -f $error_aggregator_file && -s _ );

            my $msg;

            {
                # Open the file to read the errors
                my $fh;
                if ( !open( $fh, '<', $error_aggregator_file ) ) {
                    $logger->warn("Unable to open the transport error aggregator file $error_aggregator_file for reading:  $!");
                    return;
                }

                # Slurp the file into a string
                local $/;
                $msg = readline($fh);
                close $fh;
            }

            my @upload_errors = ();
            if ( -f $serialized_error_aggregator_file && -s _ ) {
                my $serialized_logger = Cpanel::Logger::Serialized->new( 'log_file' => $serialized_error_aggregator_file );

                my $upload_errors_hr = {};

                try {
                    $serialized_logger->deserialize_entries_from_log(
                        sub {
                            my ($error_hr) = @_;

                            return if !$error_hr;
                            return if !ref $error_hr;
                            return if ref $error_hr ne 'HASH';
                            return if !keys %$error_hr;

                            # Label names should be unique per transport, which is why there isn't further checking here
                            $upload_errors_hr->{ $error_hr->{'transport'} }{ $error_hr->{'label'} } = $error_hr->{'message'};
                        },
                        sub {
                            my ( $invalid_line, $parse_error ) = @_;

                            $logger->warn( "There was an error parsing the line '$invalid_line': " . Cpanel::Exception::get_string($parse_error) );

                            return;
                        }
                    );
                }
                catch {
                    my $error = $_;

                    $logger->warn( "There was an error deserializing log entries: " . Cpanel::Exception::get_string($error) );
                };

                if ( keys %$upload_errors_hr ) {
                    for my $transport ( sort keys %$upload_errors_hr ) {
                        for my $label ( sort keys %{ $upload_errors_hr->{$transport} } ) {
                            push @upload_errors,
                              [
                                $transport,
                                $label,
                                $upload_errors_hr->{$transport}{$label},
                              ];
                        }
                    }
                }
            }

            require Cpanel::Notify;
            Cpanel::Notify::notification_class(
                'class'            => 'Backup::Transport',
                'application'      => 'Backup::Transport',
                'constructor_args' => [
                    'origin'        => 'cpbackup',
                    'upload_errors' => \@upload_errors,
                    'attach_files'  => [ { name => 'transport_errors.txt', content => \$msg, number_of_preview_lines => 25 } ]
                ]
            );

            unlink $error_aggregator_file;
            unlink $serialized_error_aggregator_file;

            return;
        }
        elsif ( $args->{'cmd'} eq 'removestaging' ) {
            my $staging_dirs_ref = $args->{'stagingdirs'};
            if ( $staging_dirs_ref->{'basedir_daily_date'} =~ m/\/\d{4}\-\d{2}\-\d{2}$/ && -d $staging_dirs_ref->{'basedir_daily_date'} ) {
                $logger->info("Removing backup staging directory: $staging_dirs_ref->{'basedir_daily_date'}");
                File::Path::rmtree( $staging_dirs_ref->{'basedir_daily_date'} );
            }
            else {
                $logger->info("$staging_dirs_ref->{'basedir_daily_date'} didn't look like a valid date directory, not removing.");
            }
            return;
        }

        ################################################################################
        # End of special command args handling. If we got here, it means we are going
        # to prune and handle the transports for remote destinations
        ################################################################################

        $self->{'transport_obj'} = Cpanel::Backup::Transport::Session->new($session_id);
        $self->{'num_retries'}   = Cpanel::Backup::Transport::get_error_threshold();

        # This will be set to 'true' if we successfully upload the file to
        # at least one remote destination
        my $file_upload_success = 0;

        # A flag to determine if system backups have been successfully uploaded
        # works like the "file_upload_success" flag above, but for system backups
        my $system_backup_upload_success = 0;

        my $transports = $self->{'transport_obj'}->get_transports();
        foreach my $transport ( keys %{$transports} ) {
            my %transport_cfg  = %{ $transports->{$transport} };
            my $transport_name = $transport_cfg{'name'};

            # If transported file is not a log, and only_used_for_logs is true, skip to next
            if ( $args->{'cmd'} ne 'log_transfer' ) {
                if ( $transport_cfg{'only_used_for_logs'} ) {
                    $logger->info("Skipping transport $transport_name since it is configured to only be used for logs.");
                    next;
                }
            }

            # Skip it if we asked for a specific transport and this isn't the transport we asked for
            next if ( $args->{'transport'} && $transport_cfg{'id'} ne $args->{'transport'} );

            # Instantiate CTF obj, fail if
            my $ctf = $self->get_ctf_obj(
                {
                    transport     => $transport,
                    logger        => $logger,
                    transport_cfg => \%transport_cfg
                }
            );

            unless ( ref $ctf ) {
                $logger->warn("Unable to get connection to transport id:  $transport");
                $self->aggregate_error( $args, $transport_name, $logger );
                next;
            }

            $logger->info( 'Starting a "' . $args->{'cmd'} . '" operation on the "' . $ctf->{'name'} . '" destination ID "' . $ctf->{'id'} . '".' );
            $logger->info( 'Base path for destination is ' . $ctf->{'path'} ) if $ctf->{'path'};

            my $perform_account_backup = 1;
            my $can_incremental        = 0;
            $can_incremental        = 1 if ( defined $ctf->{'can_incremental'} and $ctf->{'can_incremental'} == 1 );
            $perform_account_backup = 0 if ( $backup_type eq 'incremental' && !$can_incremental );

            # Handle a pruning operation
            if ( $args->{'cmd'} eq 'prune' ) {

                # Prune and go onto the next destination
                # returns an (failed,errors array)
                my ( $prune_success, $prune_errors ) = $self->attempt_to_prune_destination( $ctf, $args->{'num_to_retain'}, $args->{'appended_path'}, $logger );
                if ( !$prune_success ) {
                    $self->aggregate_error( $args, $transport_name, $logger, $prune_errors );
                }
            }
            elsif ( $args->{'cmd'} eq 'copy_system_backup' ) {

                # Only upload system backups if specifically configured for this
                if ( $transport_cfg{'upload_system_backup'} ) {

                    # Log that we are uploading a system backup file since
                    # there are some big security concerns about sending it to the wrong place
                    $logger->info("Uploading system backup file $local_path to $transport_cfg{'name'}");

                    my $success          = 0;
                    my $full_remote_path = _join_dirs( $ctf->get_path(), $remote_path );
                    if ( $self->validate_path( $ctf, $full_remote_path, $logger ) ) {

                        debug_msg("Uploading system backup $local_path to $full_remote_path (from $remote_path) ");

                        # We 'or' the results since we want to test for the case
                        # where at least one system backup upload has succeeded
                        # If the keeplocal flag is set to false, we delete the files locally
                        # after it has been uploaded; but, we only want to delete it if
                        # at least one upload attempt has passed
                        $success = $self->attempt_to_upload_file( $ctf, $local_path, $full_remote_path, $logger );
                        $system_backup_upload_success |= $success;
                    }

                    $self->aggregate_error( $args, $transport_name, $logger ) unless $success;
                }
            }
            elsif ( $args->{'cmd'} eq 'copy_backup_metadata' ) {    # Metadata (v2.0)
                                                                    # Log that we are uploading a system backup file since
                                                                    # there are some big security concerns about sending it to the wrong place
                if ($perform_account_backup) {                      # Make sure this transport can handle the type of backup we would be sending
                    $logger->info("Uploading backup metadata file $local_path to $transport_cfg{'name'}");
                    if ( !-f $local_path ) {
                        $logger->info("Backup metadata file $local_path does not appear to exist as a file on disk: $!");
                        next;
                    }
                    my $success          = 0;
                    my $full_remote_path = _join_dirs( $ctf->get_path(), $remote_path );
                    if ( $self->validate_path( $ctf, $full_remote_path, $logger ) ) {
                        debug_msg("Uploading backup metadata $local_path to $full_remote_path (from $remote_path) ");
                        $success = $self->attempt_to_upload_file( $ctf, $local_path, $full_remote_path, $logger );
                        $file_upload_success |= $success;
                    }
                    $self->aggregate_error( $args, $transport_name, $logger ) unless $success;
                }
                else {
                    $logger->info("Asked to upload backup metadata file $local_path to $transport_cfg{'name'} , however this transport does not support that backup type");
                }
            }
            else {    # Assume this is an account backup
                if ($perform_account_backup) {
                    my $success          = 0;
                    my $full_remote_path = _join_dirs( $ctf->get_path(), $remote_path );
                    my ( $history, $history_errors );
                    if ( $self->validate_path( $ctf, $full_remote_path, $logger ) ) {

                        # Upload the file
                        debug_msg("Uploading account backup $local_path to $full_remote_path (from $remote_path) ");
                        try {
                            $history = Cpanel::Backup::Transport::History->new();
                            $history->record( $transport, $date, $user );
                        }
                        catch {
                            $logger->warn( "There was a problem with the transport history database: " . Cpanel::Exception::get_string($_) );
                            push( @{$history_errors}, Cpanel::Exception::get_string($_) );
                        };

                        # We 'or' the results since we want to test for the case
                        # where at least one upload has succeeded
                        # If the keeplocal flag is set to false, we delete the file locally
                        # after it has been uploaded; but, we only want to delete it if
                        # at least one upload attempt has passed
                        $success = $self->attempt_to_upload_file( $ctf, $local_path, $full_remote_path, $logger );
                        $file_upload_success |= $success;

                        if ( $file_upload_success && $history ) {
                            try {
                                #Jot down that we actually succeeded here.
                                $history->finish( $transport, $date, $user );
                            }
                            catch {
                                $logger->warn( "There was a problem with the transport history database: " . Cpanel::Exception::get_string($_) );
                                push( @{$history_errors}, Cpanel::Exception::get_string($_) );
                            };
                        }

                    }

                    $self->_process_history_error( $args, $transport, $logger, $history_errors ) if $history_errors;
                    $self->aggregate_error( $args, $transport_name, $logger ) unless $success;
                }
            }
        }

        # If we have successfully uploaded the file and we are not keeping it local
        # Then remove the local
        if ( $file_upload_success && !$keeplocal ) {
            $logger->info("The backup has been successfully uploaded at least once, now we will delete the local copy ($local_path) since keeplocal ($keeplocal) is disabled.");
            if ( $backup_type eq 'incremental' && -d $local_path ) {
                my $err;
                File::Path::remove_tree( $local_path, { 'safe' => 1, 'error' => \$err } );
                if ( $err && @{$err} ) {
                    my $message = '';
                    foreach my $diag ( @{$err} ) {
                        my ( $file, $mesg ) = %{$diag};
                        $message .= "\n" if ( $message eq '' );
                        if ( $file ne '' ) {
                            $message .= "$file: $diag";
                        }
                        else {
                            $message .= $diag;
                        }
                    }
                    $logger->warn("Unable to delete $local_path: $message");
                }
            }
            else {
                unlink $local_path
                  or $logger->warn("Unable to delete $local_path:  $!");
            }
        }

        # If we have successfully uploaded the system backups,
        # And we are not keeping local backup files,
        # Then, go ahead and get rid of the local system backup files
        if ( $system_backup_upload_success && !$keeplocal ) {
            purge_system_backup( $logger, $args->{'local_files'} );
        }

        # Remove local directory structure once it's emptied of all it's archives.
        if ( !$keeplocal ) {

            # Get the base dir for the backup operation.
            my $local_dir = File::Basename::dirname($local_path);
            $local_dir =~ s{(^.*)/.*$}{$1};

            # Make sure we account for dotfiles (for metadata v2.0, since glob will skip them by default
            my @files = File::Glob::bsd_glob("$local_dir/*/{.[!.],.??*,*}");

            # Need to avoid rm'ing the directory if the backup_incomplete flag file is still present or it may not be available for uploading
            if ( scalar @files == 0 && !-e "$local_dir/backup_incomplete" ) {
                $logger->info("There are no more files or directories in the backup path and keeplocal ($keeplocal) is disabled, so now we will delete $local_dir entirely.");
                File::Path::remove_tree( $local_dir, { 'safe' => 1 } );
            }
        }

        return;
    }

    #
    # Get rid of the local system backup files
    # (Assumes we have uploaded it somewhere)
    #
    sub purge_system_backup {
        my ( $logger, $system_backup_folder ) = @_;

        # The system backup folder should have been supplied
        if ( !defined $system_backup_folder or $system_backup_folder eq '' ) {
            $logger->warn("purge_system_backup called without a system backup directory");
            return;
        }

        # The system backup folder should be an actual valid directory
        if ( !-d $system_backup_folder ) {
            $logger->warn("The system backup directory, $system_backup_folder, is not a valid directory");
            return;
        }

        # We could just recursively delete the system backup folder
        # directly; but, this seems kind of dangerous.
        # Instead, I'll recursively delete the special directories
        # we expect to see under it, then remove the system backup
        # directory.

        # Backup directory will contain a "dirs" and "files" directory
        foreach my $subdir (qw/dirs files/) {

            my $subdir_full_path = File::Spec->catdir( $system_backup_folder, $subdir );

            File::Path::remove_tree($subdir_full_path);

            if ( -e $subdir_full_path ) {
                $logger->warn("Unable to delete:  $subdir_full_path");
            }
        }

        # Remove the actual directory
        if ( !rmdir $system_backup_folder ) {
            $logger->warn("Unable to remove, $system_backup_folder:  $!");
        }

        return;
    }

    #
    # Aggregate a top level transport error into a file and serializes the error into another
    # so we can send all the errors to the admin when we are done transporting files
    #
    sub aggregate_error {
        my ( $self, $args, $transport_name, $logger, $notable_errors ) = @_;

        my $command    = $args->{'cmd'};
        my $local_path = $args->{'local_path'};

        my $msg;
        if ( $command eq 'prune' ) {
            $msg = $locale->maketext( "Unable to prune transport “[_1]”", $transport_name );
        }
        elsif ( $command eq 'history' ) {
            $msg = $locale->maketext("There was a problem with the transport history database.");
        }
        else {
            $msg = $locale->maketext( "Unable to send “[_1]” to destination “[_2]”", $local_path, $transport_name );
        }

        my $error_opts = {
            'logger'         => $logger,
            'notable_errors' => $notable_errors,
            'message'        => $msg,
            'transport'      => $transport_name,
        };
        $self->_aggregate_error_to_log_file( $args, $error_opts );

        # Only serialize upload errors
        if ( $command ne 'prune' ) {
            $self->_serialize_error_to_aggregate_file( $args, $error_opts );
        }

        return;
    }

    sub _aggregate_error_to_log_file {
        my ( $self, $args, $opts ) = @_;

        my ( $command, $error_aggregator_file ) = @{$args}{qw( cmd error_aggregator_file )};
        my ( $logger, $message, $notable_errors ) = @{$opts}{qw(logger message notable_errors)};

        if ( !$error_aggregator_file ) {
            $logger->warn("Command '$command' invoked with out an aggregator error file");
            return;
        }

        my $fh;
        if ( !Cpanel::FileUtils::Open::sysopen_with_real_perms( $fh, $error_aggregator_file, 'O_WRONLY|O_APPEND|O_CREAT', 0640 ) ) {
            $logger->warn("Unable to open the transport error aggregator file '$error_aggregator_file' for writing:  $!");
            return;
        }

        print {$fh} "$message\n";
        if ($notable_errors) {
            print {$fh} join( "\n", @{$notable_errors} ) . "\n";
        }

        close $fh;

        return;
    }

    sub _serialize_error_to_aggregate_file {
        my ( $self, $args, $opts ) = @_;

        my $upload_label = $args->{'user'} || 'System Backup';
        my ( $command, $serialized_error_aggregator_file ) = @{$args}{qw( cmd serialized_error_aggregator_file )};
        my ( $logger, $message, $transport ) = @{$opts}{qw( logger message transport )};

        if ( !$serialized_error_aggregator_file ) {
            $logger->warn("Command '$command' invoked without a serialized error aggregator file");
            return;
        }

        try {
            my $serialized_logger = Cpanel::Logger::Serialized->new( 'log_file' => $serialized_error_aggregator_file );

            # Currently only the 'prune' command produces 'notable_errors'
            # If that changes, please update this and the iContact notification message
            $serialized_logger->serialize_entry_to_log(
                {
                    'label'     => $upload_label,
                    'transport' => $transport,
                    'message'   => $message,
                }
            );
        }
        catch {
            my $error = $_;

            $logger->warn( "There was an error serializing the a log entry for the label '$upload_label' during the command '$command': " . Cpanel::Exception::get_string($error) );
        };

        return;
    }

    #
    # Return the number of seconds we will wait for a restore to complete
    #
    sub get_timeout {

        # Max time we allow a file upload
        return Cpanel::Backup::Config::get_valid_value_for('maximum_timeout');
    }

    # Return a Cpanel::Transport::Files object
    # params: the transport_id, the Cpanel::Backup::Transport object and the hash containing all the config data for the transport
    sub get_ctf_obj {
        my ( $self, $transport_data_ref ) = @_;
        my $transport         = $transport_data_ref->{'transport'};
        my $logger            = $transport_data_ref->{'logger'};
        my $transport_cfg_ref = $transport_data_ref->{'transport_cfg'};
        my $type              = delete $transport_cfg_ref->{'type'};

        debug_msg("Instantiating Object");

        my $ctf;

        for ( 1 .. $self->{'num_retries'} ) {
            eval {
                $ctf = Cpanel::Transport::Files->new( $type, $transport_cfg_ref );
                $ctf->{'transport_id'} = $transport;
            };
            if ($@) {
                if ( ref $@ eq 'Cpanel::Transport::Exception::Network::Authentication' ) {

                    # do not attempt again if it's an authentication failure
                    $logger->warn("Disabling remote backup destination due to authentication failure:  $transport_cfg_ref->{'name'}");

                    $self->{'transport_obj'}->disable( $transport, 'Could not authenticate' );
                    last;
                }
                elsif ( ref $@ eq 'Cpanel::Transport::Exception' ) {
                    $logger->warn( "Error connecting to $transport_cfg_ref->{'name'}:  " . $@->message );
                }
                else {
                    $logger->warn("Error connecting to $transport_cfg_ref->{'name'}:  $@");
                }
            }
            else {

                # No more retries if we have succeeded
                return $ctf;
            }
        }

        # Failed all the retries
        return undef;
    }

    #
    # Upload our backup file to the remote destination
    #
    sub attempt_to_upload_file {
        my ( $self, $ctf, $local_path, $remote_path, $logger ) = @_;

        # try to upload 3 times before failing
        debug_msg( "Attempting to upload $local_path to $remote_path for destination:  " . $ctf->{'name'} );

        for my $attempt_number ( 1 .. $self->{'num_retries'} ) {
            $logger->info( "Upload attempt #$attempt_number starting for $local_path to $remote_path for destination:  " . $ctf->{'name'} );

            # Make sure the timeout is set for each attempt
            local $SIG{'ALRM'} = sub { die "Time out reached for upload attempt #$attempt_number\n"; };
            my $orig_alarm = alarm( get_timeout() );

            ###########################################################################################
            # Incremental backups need to use a special handler rather than putting one file at a time
            ###########################################################################################

            if ( defined( $ctf->{'can_incremental'} ) and $ctf->{'can_incremental'} == 1 ) {    # and incremental is enabled locally
                if ( $ctf->can('_put_inc') ) {
                    eval { $ctf->_put_inc( $local_path, $remote_path ); };
                    if ($@) {
                        my $message = $@;
                        $message = $message->message if eval { $message->can('message') };
                        $logger->warn( "Upload attempt failed: " . $message );

                        # If a connection gets temporarily interrupted, make the connection object rebuild itself
                        # so as to prevent needlessly cascading failures. See CPANEL-3338 for more information.
                        $ctf = $ctf->rebuild();
                    }
                    else {
                        debug_msg( "Successful incremental transfer of $local_path to $remote_path for destination " . $ctf->{'name'} );
                        alarm $orig_alarm;
                        return 1;
                    }
                }
                else {
                    $logger->info("Can't use put_inc in transport");
                    debug_msg( "Destination transport " . $ctf->{'name'} . " does not support transporting directories, skipping as this is an incremental backup." );
                    alarm $orig_alarm;
                    return 1;
                }

            }
            else {
                eval { $ctf->put( $local_path, $remote_path ); };
                if ($@) {
                    my $message = $@;
                    $message = $message->message if eval { $message->can('message') };
                    $logger->warn( "Upload attempt failed: " . $message );

                    # If a connection gets temporarily interrupted, make the connection object rebuild itself
                    # so as to prevent needlessly cascading failures. See CPANEL-3338 for more information.
                    $ctf = $ctf->rebuild();
                }
                else {
                    debug_msg( "Successful transfer of $local_path to $remote_path for destination " . $ctf->{'name'} );
                    alarm $orig_alarm;
                    return 1;
                }
            }

            alarm $orig_alarm;
        }
        return 0;
    }

    sub attempt_to_prune_destination {
        my ( $self, $ctf, $num_to_retain, $path_to_append, $logger ) = @_;

        my $failed = 0;
        my @errors;

        debug_msg( "Performing prune operation, retaining $num_to_retain items on:  " . $ctf->{'name'} );

        # Retention can not be less than one
        return 1 if ( $num_to_retain < 1 );

        my $basedir = $ctf->get_path();

        # If a subdirectory, like "weekly" or "monthly" is specified, then append it
        if ($path_to_append) {
            $basedir = _join_dirs( $basedir, $path_to_append );
        }

        # Get the contents of the directory
        my $ls_res;
        eval { $ls_res = $ctf->ls($basedir); };
        if ($@) {
            my $message = $@;
            $message = $message->message if eval { $message->can('message') };
            $logger->warn( "Unable to prune:  " . $message );
            chomp($message);
            push @errors, $locale->maketext( "Unable to remove outdated backup: [_1]", $message );
            return ( 0, \@errors );
        }
        unless ( ( defined $ls_res ) && ( $ls_res->{'success'} ) ) {
            $logger->warn("Performing ls on $basedir failed; can not prune");
            push @errors, $locale->maketext( "The system cannot remove outdated backups because it cannot read the contents of the directory: [_1]", $basedir );
            return ( 0, \@errors );
        }

        my @backup_dirs = ();

        foreach my $entry ( @{ $ls_res->{'data'} } ) {

            # It has to be a directory, of course
            next unless ( $entry->{'type'} eq 'directory' );

            # Only get the ones formated YYYY-MM-DD
            next unless $entry->{'filename'} =~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}\/?$/;

            push( @backup_dirs, _join_dirs( $basedir, $entry->{'filename'} ) );
        }

        # This will arrange them oldest to newest
        # since they are all named YYYY-MM-DD
        @backup_dirs = sort @backup_dirs;

        # Find our newest good backup, and remove it from the array
        my $backup_removed = 0;    # we might not actually *have* a good one
      FIND_GOOD_BACKUP:
        for ( my $i = @backup_dirs - 1; $i >= 0; $i-- ) {
            local $@;

            # Get the contents of the directory
            # This could be so much simpler, for *some* types of remotes,
            # but let's not assume that. That said, we don't really care
            # why we fail here very much; just don't do the prune.
            my $ls_res_deep;
            eval { $ls_res_deep = $ctf->ls( $backup_dirs[$i] ); };
            if ( $@ || !defined $ls_res_deep || !$ls_res_deep->{'success'} ) {
                my $message = $@;
                $logger->warn("Performing ls on $backup_dirs[$i] failed: $message");
                chomp($message);
                push @errors, $locale->maketext( "The system cannot remove outdated backups because it cannot read the contents of the directory: [_1]", $backup_dirs[$i] );

                return ( 0, \@errors );
            }
            my $found = 0;
            foreach my $entry_deep ( @{ $ls_res_deep->{'data'} } ) {
                next unless $entry_deep->{'filename'} eq 'backup_incomplete';
                $found++;    # This is a bad backup.
            }
            if ( !$found ) {
                splice( @backup_dirs, $i, 1 );
                $backup_removed++;
                last FIND_GOOD_BACKUP;
            }
        }

        # We have too many
        my $dir_to_remove;
        while ( @backup_dirs > $num_to_retain - $backup_removed ) {

            # The first will be the oldest
            $dir_to_remove = shift @backup_dirs;
            chomp($dir_to_remove);
            debug_msg( "Pruning backup directory:  $dir_to_remove, from " . $ctf->{'name'} );

            # Delete the whole backup file tree
            eval { $ctf->rmdir($dir_to_remove); };
            if ($@) {
                my $message = $@;
                $message = $message->message if eval { $message->can('message') };
                chomp($message);

                # warn() causes backtraces and makes it pretty ugly to read
                $logger->info( "ERROR: Pruning $dir_to_remove from " . $ctf->{'name'} . ":  " . $message );
                $logger->info("The system could not prune the “$dir_to_remove” directory due to an error.");
                $logger->info("Read the go.cpanel.net/directorypruning documentation for solutions to successfully prune the directory.");
                push @errors, $locale->maketext( "Error pruning “[_1]” from “[_2]”: [_3]", $dir_to_remove, $ctf->{'name'}, $message );
                push @errors, $locale->maketext( "The system could not prune the “[_1]” directory due to an error.", $dir_to_remove );
                push @errors, $locale->maketext("Read the go.cpanel.net/directorypruning documentation for solutions to successfully prune the directory.");
                $failed = 1;
            }
        }

        if ($failed) {

            # Loudly alert the admin that there are critical issues with backup transports
            require Cpanel::Notify;
            Cpanel::Notify::notification_class(
                'class'            => 'Backup::Transport',
                'application'      => 'Backup::Transport',
                'constructor_args' => [
                    'origin'        => 'backup',
                    'upload_errors' => \@errors,
                    'attach_files'  => [ { name => 'transport_errors.txt', content => \@errors, number_of_preview_lines => 25 } ]
                ]
            );
        }

        #Remove the relevant entries from the backup history database.
        #Do this regardless of whether a prune failed, as this could be a 'partial' failure resulting in a 'partial' backup being available for restore.
        #Note above that I am being clever with $dir_to_remove and only grabbing the 'latest' dir to remove, as this method prunes everything before said date.
        if ($dir_to_remove) {
            my $history = Cpanel::Backup::Transport::History->new();
            $history->prune_by_date( File::Basename::basename($dir_to_remove) );
        }

        return ( $failed ? 0 : 1, \@errors );
    }

    #
    # Try to validate the path multiple times until failure
    #
    sub validate_path {
        my ( $self, $ctf_obj, $path, $logger ) = @_;

        for ( 1 .. $self->{'num_retries'} ) {

            # If it succeeds, then we are done
            return 1 if $self->_validate_path( $ctf_obj, $path, $logger );
        }

        # Still failed after all the retries
        return 0;
    }

    # Check if the destination path exists, create if it doesn't.
    sub _validate_path {
        my ( $self, $ctf_obj, $path, $logger ) = @_;
        my $transport_id = $ctf_obj->{'transport_id'};

        my $full_destination_dir = $path;

        my ( $remote_filename, $remote_path, $suffix ) = File::Basename::fileparse($path);

        # Remove the filename from the path if path is to a file rather than a directory
        if ( $remote_filename =~ m/\.tar(\.gz|\.bz2)?$/ or $remote_filename =~ m/^\.master\.meta$/ or $remote_filename =~ m/^\.sql_dump.gz$/ or $remote_filename =~ m/^backup_incomplete$/ ) {
            $full_destination_dir = $remote_path;

            # If our original path was relative, keep it relative here
            if ( $path !~ m/^\// ) {
                $full_destination_dir =~ s/^\///;
            }
        }

        eval {
            debug_msg("Validating destination path $full_destination_dir");
            $ctf_obj->ls($full_destination_dir);
        };

        # If this doesn't throw an error the path should already exist.
        if ( !$@ ) {
            debug_msg("Path exists");
            return 1;
        }

        eval {

            # make recursively
            debug_msg("Making Path $full_destination_dir");
            $ctf_obj->mkdir($full_destination_dir);
        };
        if ( !$@ ) {
            debug_msg("Path creation successful");
            return 1;
        }
        else {
            my $message = $@;
            $message = $message->message if eval { $message->can("message") };
            $logger->warn("Path creation failed:  $message");
        }

        return 0;
    }

    sub debug_msg {
        my ($msg) = @_;
        print STDERR "$msg\n" if $debug;
        return;
    }

    sub _join_dirs {
        my (@dirs) = @_;
        my $path = File::Spec->catdir(@dirs);
        $path =~ s{^/}{} if $dirs[0] !~ m{^/};
        return $path;
    }

    sub _process_history_error {
        my ( $self, $args, $transport, $logger, $err ) = @_;
        $args->{cmd} = "history";
        return $self->aggregate_error( $args, $transport, $logger, $err );
    }
}

sub to_register {
    return (
        [ 'backup_transport', Cpanel::Backup::Queue::transport_backup->new() ],    # PPI NO PARSE - Included inside of this file
    );

}

1;
