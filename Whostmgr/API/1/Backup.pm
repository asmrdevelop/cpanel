package Whostmgr::API::1::Backup;

# cpanel - Whostmgr/API/1/Backup.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::SafeRun::Errors ();
use Cpanel::SafeRun::Object ();
use Cpanel::CloseFDs        ();
use Cpanel::Exception       ();
use Cpanel::Locale          ();
use MIME::Base64            ();
use Whostmgr::ACLS          ();
use Whostmgr::API::1::Utils ();

use constant NEEDS_ROLE => {
    list_cparchive_files                          => undef,
    restoreaccount                                => undef,
    backup_generate_google_oauth_uri              => undef,
    backup_does_client_id_have_google_credentials => undef,
    backup_destination_add                        => undef,
    backup_destination_validate                   => undef,
    backup_destination_delete                     => undef,
    backup_destination_list                       => undef,
    backup_destination_get                        => undef,
    backup_destination_set                        => undef,
    backup_config_get                             => undef,
    backup_config_set                             => undef,
    backup_skip_users_all                         => undef,
    backup_skip_users_all_status                  => undef,
    backup_set_list                               => undef,
    backup_set_list_combined                      => undef,
    backup_date_list                              => undef,
    backup_user_list                              => undef,
    list_transported_backups                      => undef,
    get_transport_status                          => undef,
    get_users_and_domains_with_backup_metadata    => undef,
    get_users_with_backup_metadata                => undef,
    start_background_pkgacct                      => undef,
    restore_queue_add_task                        => undef,
    restore_queue_clear_pending_task              => undef,
    restore_queue_clear_all_tasks                 => undef,
    restore_queue_clear_all_pending_tasks         => undef,
    restore_queue_clear_completed_task            => undef,
    restore_queue_clear_all_completed_tasks       => undef,
    restore_queue_clear_all_failed_tasks          => undef,
    restore_queue_list_pending                    => undef,
    restore_queue_list_active                     => undef,
    restore_queue_state                           => undef,
    restore_queue_list_completed                  => undef,
    restore_queue_is_active                       => undef,
    restore_queue_activate                        => undef,
    toggle_user_backup_state                      => undef,
    convert_and_migrate_from_legacy_config        => undef,
    fetch_pkgacct_master_log                      => undef,
    get_pkgacct_session_state                     => undef,
};

my @sanitize_ignore = qw/id name type disabled sessions upload_system_backup only_used_for_logs/;

#
# Method to get list of cparchive files.  Important to pull this out since
#   we found resellers with large user sets would freeze on attempting to hit the page
#   that used this previously.
#
sub list_cparchive_files {
    ## no args
    my ( $args, $metadata ) = @_;
    require Whostmgr::Transfers::Locations;
    my ( $ok, $files ) = Whostmgr::Transfers::Locations::get_quickrestore_files();
    if ( !$ok ) {
        @{$metadata}{qw(result reason)} = ( 0, $files );
        return;
    }

    $metadata->{'result'} = scalar $files         ? 1    : 0;
    $metadata->{'reason'} = $metadata->{'result'} ? 'OK' : 'No matching files found.';
    return if !$metadata->{'result'};
    return { 'quickrestore_files' => $files };
}

sub restoreaccount {
    my ( $args, $metadata ) = @_;

    foreach my $required (qw(user type)) {
        if ( !length $args->{$required} ) {
            die Cpanel::Exception::create( 'MissingParameter', [ 'name' => $required ] );
        }
    }

    require Whostmgr::Backup::Restore::Legacy;
    my ( $result, $reason_or_transfer_session_id ) = Whostmgr::Backup::Restore::Legacy::enqueue_restore_backup(
        'db_restore_method'     => 'overwrite_all',
        'dbuser_restore_method' => 'overwrite_all',
        'user'                  => $args->{'user'},
        'restoretype'           => $args->{'type'},
        'restoreip'             => ( $args->{'ip'}    ? 1 : 0 ),
        'restoremail'           => ( $args->{'mail'}  ? 1 : 0 ),
        'restoremysql'          => ( $args->{'mysql'} ? 1 : 0 ),
        'restorepsql'           => 1,
        'restorebwdata'         => 1,
        'restoresubs'           => ( $args->{'subs'} ? 1 : 0 ),
    );
    $metadata->{'result'} = $result;
    $metadata->{'reason'} = $reason_or_transfer_session_id;
    if ( !$result ) {
        return;
    }

    require Whostmgr::Transfers::Session::Start;
    my ( $start_ok, $pid_or_error ) = Whostmgr::Transfers::Session::Start::start_transfer_session($reason_or_transfer_session_id);

    if ( !$start_ok ) {

        $metadata->{'reason'} = $pid_or_error;
        return;
    }

    $metadata->{'reason'} = "Account Restoring in background";    # Not localized for compat

    $metadata->{'output'}{'raw'} = _locale()->maketext( "The system will restore the backup in the background with a transfer session ID of “[_1]”.", $reason_or_transfer_session_id );
    return { 'transfer_session_id' => $reason_or_transfer_session_id, 'pid' => $pid_or_error };
}

#
# Generate a URI to get an oauth token from google access credentials
#
sub backup_generate_google_oauth_uri {
    my ( $args, $metadata ) = @_;

    my $client_id     = $args->{'client_id'};
    my $client_secret = $args->{'client_secret'};

    if ( ( !defined $client_id ) || ( !defined $client_secret ) ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = "Missing arguments";
        return;
    }

    my $script_run = Cpanel::SafeRun::Object->new(
        'program'     => '/usr/local/cpanel/scripts/generate_google_drive_oauth_uri',
        'before_exec' => sub {
            $ENV{'GOOGLE_CLIENT_ID'}     = $client_id;        ## no critic qw(Variables::RequireLocalizedPunctuationVars) -- need child to inherit
            $ENV{'GOOGLE_CLIENT_SECRET'} = $client_secret;    ## no critic qw(Variables::RequireLocalizedPunctuationVars) -- need child to inherit
        },
    );

    my $output = $script_run->stdout();

    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';

    return { 'uri' => $output };
}

#
# For a given client id, has a credential file been generated
#
sub backup_does_client_id_have_google_credentials {
    my ( $args, $metadata ) = @_;

    my $client_id = $args->{'client_id'};

    if ( !defined $client_id ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = "Missing arguments";
        return;
    }

    require Cpanel::Transport::Files::GoogleDrive::CredentialFile;
    my $credentials_file = Cpanel::Transport::Files::GoogleDrive::CredentialFile::credential_file_from_id($client_id);

    my $exists = ( -f $credentials_file ) ? 1 : 0;

    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';

    return { 'exists' => $exists };
}

#
# Add a new backup transport
#
sub backup_destination_add {
    my ( $args, $metadata ) = @_;

    # All must possess a name and type
    my $name = $args->{'name'};
    my $type = $args->{'type'};

    unless ( defined $name and defined $type ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = "Missing arguments";
        return;
    }

    require Cpanel::Backup::Transport;
    if ( !Cpanel::Backup::Transport::validate_common( $args, $metadata ) ) {
        return;
    }

    # Sanitize the params as well
    require Cpanel::Transport::Files;
    Cpanel::Transport::Files::sanitize_parameters( $type, $args, \@sanitize_ignore );

    my $transport = Cpanel::Backup::Transport->new();

    # Make sure 'id' is empty, it will be generated by the 'add' call
    delete $args->{'id'};

    # If 'disabled' was not specified, then set to false
    $args->{'disabled'} = 0 unless exists $args->{'disabled'};

    my $id = $transport->add(%$args);
    if ($id) {
        $metadata->{'result'} = 1;
        $metadata->{'reason'} = 'OK';
    }
    else {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $transport->get_error_msg();
    }

    return { 'id' => $id };
}

#
# Validate config for a backup destination
#
# Requires:     id, disableonfail
# Returns:      pass/fail, details msg
#
sub backup_destination_validate {
    my ( $args, $metadata ) = @_;

    # We require an ID for the destination
    my $id  = $args->{'id'};
    my $dof = $args->{'disableonfail'};

    unless ( defined $id ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = "Missing argument:  id";
        return;
    }
    unless ( defined $dof ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = "Missing argument:  disableonfail";
        return;
    }
    unless ( $dof == 0 || $dof == 1 ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = "Value for argument disableonfail must be either 1 or 0 ($dof)";
        return;
    }

    my $cli_args = _make_command_line_args($args);

    # pass off the heavy lifting to script called via CLI to avoid loading modules using binary WHM that doesn't have them

    my @output = Cpanel::SafeRun::Errors::saferunnoerror( '/usr/local/cpanel/bin/backup_cmd', $cli_args );
    foreach my $line (@output) {
        if ( $line =~ m/^response:id=(.*)$/ ) {
            $id = $1;
        }
        elsif ( $line =~ m/^metadata:(.*?)=(.*)$/ ) {
            $metadata->{$1} = $2;
        }
    }
    return { 'id' => $id };
}

#
# Delete a backup destination
#
# Requires:     id
# Returns:      pass/fail
#
sub backup_destination_delete {
    my ( $args, $metadata ) = @_;

    # We require an ID for the destination to delete
    my $id = $args->{'id'};
    unless ( defined $id ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = "Missing argument:  id";
        return;
    }

    require Cpanel::Backup::Transport;
    my $transport = Cpanel::Backup::Transport->new();

    if ( $transport->delete($id) ) {
        require Cpanel::Backup::Transport::History;
        my $history = Cpanel::Backup::Transport::History->new();
        $history->prune_by_transport($id);

        $metadata->{'result'} = 1;
        $metadata->{'reason'} = 'OK';
    }
    else {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $transport->get_error_msg();
    }

    return;
}

#
# Get a list of configured backup destinations
#
# Returns:
# {
#   'destination_list' => [
#       {
#           %destination_config,
#           'id' => $id,
#       },
#       ...
#   ]
# }
#
sub backup_destination_list {
    my ( $args, $metadata ) = @_;

    my @binary_params = qw|ssl mount no_mount_fail|;

    require Cpanel::Backup::Transport;
    my $dest_hash = Cpanel::Backup::Transport::get_destinations();

    my @result_list = map {
        my $id     = $_;
        my $config = $dest_hash->{$id};
        _clean_destination_config($config);
        $config->{'id'} = $id;

        # this value is parsed as a string through our API and handlebars will always see this as truthy, negating #if conditionals
        # so instead of returning 0, we return a null string so it will be false.
        foreach my $param (@binary_params) {
            if ( defined( $config->{$param} ) ) {
                unless ( $config->{$param} == 1 ) {
                    $config->{$param} = '';
                }
            }
        }
        $config;
    } keys %{$dest_hash};

    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';

    # $metadata->{'output'}{'destination_list'} = \@result_list;

    return { 'destination_list' => \@result_list };
}

#
# Get the backup destination config
#
# Required:     id
# Returns:      backup destination config
#
sub backup_destination_get {
    my ( $args, $metadata ) = @_;

    # We require an ID for the destination to delete
    my $id = $args->{'id'};
    unless ( defined $id ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = "Missing argument:  id";
        return;
    }

    require Cpanel::Backup::Transport;
    my $transport = Cpanel::Backup::Transport->new();

    # Get the backup destination config
    my $config = $transport->get($id);

    if ( defined $config ) {

        # Make sure no passwords are returned
        _clean_destination_config($config);

        $metadata->{'result'} = 1;
        $metadata->{'reason'} = 'OK';

        # $metadata->{'output'} = $config;
    }
    else {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $transport->get_error_msg();
    }

    return $config;
}

#
# Set params for backup destination config
#
# Required:     id
# Optionnal:    params to redefine
# Returns:      success/fail
#
sub backup_destination_set {
    my ( $args, $metadata ) = @_;

    # We require an ID for the destination to delete
    my $id = $args->{'id'};
    unless ( defined $id ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = "Missing argument:  id";
        return;
    }

    require Cpanel::Backup::Transport;
    my $transport = Cpanel::Backup::Transport->new();

    # Get the backup destination config
    my $config = $transport->get($id);

    # For a 'set' operation, we expect the original to be there
    unless ( defined $config ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $transport->get_error_msg();
        return;
    }

    # set the new params in the config object
    foreach my $key ( keys %$args ) {
        $config->{$key} = $args->{$key};
    }

    # The type for the backup destination, need for validation
    my $type = $config->{'type'};
    my $name = $config->{'name'};

    # Validate the type
    require Cpanel::Transport::Files;
    if ( !Cpanel::Transport::Files::is_transport_type_valid($type) ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = "The backup destination type is invalid:  $type";
        return;
    }

    # Test all of our params
    my @missing = Cpanel::Transport::Files::missing_parameters( $type, $config );
    if (@missing) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = "The following parameters were missing:  @missing";
        return;
    }

    # Test all of our params
    my @invalid = Cpanel::Transport::Files::validate_parameters( $type, $config );
    if (@invalid) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = "The following parameters were invalid:  @invalid";
        return;
    }

    # Sanitize the params as well
    Cpanel::Transport::Files::sanitize_parameters( $type, $config, \@sanitize_ignore );

    # save the config info back again
    if ( $transport->add(%$config) ) {
        $metadata->{'result'} = 1;
        $metadata->{'reason'} = 'OK';
    }
    else {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $transport->get_error_msg();
    }

    return;
}

sub backup_config_get {
    my ( undef, $metadata ) = @_;
    require Cpanel::Backup::Config;
    my $backup_config = Cpanel::Backup::Config::get_normalized_config();
    if ( ref $backup_config eq 'HASH' ) {
        $metadata->{'result'} = 1;
        $metadata->{'reason'} = 'OK';
        return { 'backup_config' => $backup_config };
    }
    else {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = 'Unknown Error';
        return;
    }
}

sub backup_config_set {
    my ( $args, $metadata ) = @_;
    require Cpanel::Backup::Config;
    my ( $ret, $msg ) = Cpanel::Backup::Config::save($args);
    if ( $ret == 1 ) {
        $metadata->{'result'} = $ret;
        $metadata->{'reason'} = $msg;
    }
    else {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $msg ? $msg : 'Unknown Error';

    }
    return;
}

sub backup_skip_users_all {
    my ( $args, $metadata ) = @_;
    if ( !exists $args->{'state'} ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = 'state must be specified';
        return;
    }
    require Cpanel::Backup::SkipUsers;
    my ( $retcode, $msg ) = Cpanel::Backup::SkipUsers::update_all_users_files($args);
    $metadata->{'result'} = $retcode;
    $metadata->{'reason'} = $msg;
    return;
}

sub backup_skip_users_all_status {
    my ($metadata) = @_;
    require Cpanel::Backup::SkipUsers;
    my ( $retcode, $msg ) = Cpanel::Backup::SkipUsers::set_all_status($metadata);
    $metadata->{'result'} = $retcode;
    $metadata->{'reason'} = $msg;
    return;
}

sub _do_db_pagination {
    my ( $metadata, $api_args ) = @_;

    #Handle pagination properly
    my %opts;
    if ( ref $api_args->{chunk} eq 'HASH' && $api_args->{chunk}->{enable} ) {
        $opts{limit}  = $api_args->{chunk}->{size};
        $opts{offset} = $api_args->{chunk}->{start};

        if ( $opts{offset} && !$opts{limit} ) {
            $metadata->{'result'} = 0;
            $metadata->{'reason'} = 'backup_set_list cannot satisfy api.chunk.start withou api.chunk.size';
            return;
        }

        #Tell the apply() function we've already paginated the data
        $metadata->{'__chunked'} = 1;
    }
    return %opts;
}

sub backup_set_list_combined {
    my ( $args, $metadata, $api_args ) = @_;

    require Cpanel::Backup::Config;
    require Cpanel::Backup::BackupSet;
    require Cpanel::Backup::Transport;
    require Cpanel::Backup::Transport::History;

    my $local_backups  = [];
    my $remote_backups = [];

    my $conf = Cpanel::Backup::Config::load();

    # Get local backups
    $local_backups = Cpanel::Backup::BackupSet::backup_set_list();

    # Get remote backups
    my %opts    = _do_db_pagination( $metadata, $api_args );
    my $history = Cpanel::Backup::Transport::History->new();
    $remote_backups = $history->get();

    # create hash of data keyed on user from all available backup sources
    my %detailed_backups_list;

    foreach my $loc_backup ( @{$local_backups} ) {
        foreach my $backup_date ( @{ $loc_backup->{'backup_date'} } ) {
            push(
                @{ $detailed_backups_list{ $loc_backup->{'user'} } },
                {
                    'where' => 'local',
                    'when'  => $backup_date
                }
            );
        }
    }

    my $destinations = Cpanel::Backup::Transport::get_destinations();
    foreach my $rem_backup ( @{$remote_backups} ) {

        # Filter out non-FTP remotes... for now.
        next unless grep { $_ eq $rem_backup->{'transport'} && $destinations->{$_}{'type'} eq 'FTP' } keys(%$destinations);
        push(
            @{ $detailed_backups_list{ $rem_backup->{'user'} } },
            {
                'where' => $rem_backup->{'transport'},
                'when'  => $rem_backup->{'date'}
            }
        );
    }

    # Get list of remote destinations and return id = name for UI
    my $destination_legend;
    foreach my $dest_id ( keys %{$destinations} ) {
        $destination_legend->{$dest_id} = {
            'name' => $destinations->{$dest_id}{'name'},
            'type' => $destinations->{$dest_id}{'type'},
        };
    }
    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';
    return {
        'backup_set'         => ( \%detailed_backups_list ),
        'destination_legend' => $destination_legend
    };
}

#
# Get a hash of all the accounts backed to a list of the backup
# dates for each account
#
sub backup_set_list {
    my ( $args, $metadata, $api_args ) = @_;

    my $results = [];
    require Cpanel::Backup::Config;
    my $conf = Cpanel::Backup::Config::load();
    if ( $conf->{KEEPLOCAL} == 0 ) {
        my %opts = _do_db_pagination( $metadata, $api_args );

        require Cpanel::Backup::Transport::History;
        my $history = Cpanel::Backup::Transport::History->new();
        my %reshash = $history->get_grouped_uniques( 'user', 'date', %opts );
        @$results = map { { 'user' => $_, backup_date => $reshash{$_} } } keys(%reshash);
    }
    else {
        require Cpanel::Backup::BackupSet;
        $results = Cpanel::Backup::BackupSet::backup_set_list();
    }

    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';
    return { 'backup_set' => $results };
}

#
# Gets just a list of all the dates for which we have backups
#
sub backup_date_list {
    my ( $args, $metadata, $api_args ) = @_;
    my $results = [];

    require Cpanel::Backup::Config;
    my $conf = Cpanel::Backup::Config::load();
    if ( $conf->{KEEPLOCAL} == 0 ) {
        my %opts = _do_db_pagination( $metadata, $api_args );

        require Cpanel::Backup::Transport::History;
        my $history = Cpanel::Backup::Transport::History->new();
        $results = $history->get(
            sort_order   => 'DESC',
            sort_key     => 'date',
            unique_field => 'date',
            limit        => $opts{limit},
            offset       => $opts{offset},
        );
        @$results = map { $_->{date} } @$results;
    }
    else {
        require Cpanel::Backup::BackupSet;
        $results = Cpanel::Backup::BackupSet::backup_date_list();
    }

    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';
    return { 'backup_set' => $results };
}

#
# List all the backed up users for a specific date
#
sub backup_user_list {
    my ( $args, $metadata, $api_args ) = @_;
    unless ( $args->{'restore_point'} ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = 'Missing argument:  restore_point';
        return;
    }
    my ( $rc, $result );

    require Cpanel::Backup::Config;
    my $conf = Cpanel::Backup::Config::load();
    if ( $conf->{KEEPLOCAL} == 0 ) {
        my %opts = _do_db_pagination( $metadata, $api_args );

        require Cpanel::Backup::Transport::History;
        my $history = Cpanel::Backup::Transport::History->new();
        $result = $history->get(
            unique_field => 'user',
            search_field => 'date',
            search_term  => $args->{restore_point},
            limit        => $opts{limit},
            offset       => $opts{offset},
        );

        #If they're in the DB, they're active, as we reap as part of killacct
        @$result = map { { 'status' => 'active', 'username' => $_->{user} } } @$result;
        $rc      = !!scalar(@$result);
        $result  = "Invalid restore point: $args->{restore_point}" if ( !@$result );
    }
    else {
        require Cpanel::Backup::BackupSet;
        ( $rc, $result ) = Cpanel::Backup::BackupSet::backup_user_list( $args->{'restore_point'} );
    }

    if ($rc) {
        $metadata->{'result'} = 1;
        $metadata->{'reason'} = 'OK';
        return { 'user' => $result };
    }
    else {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $result;
        return;
    }
}

#
# List all backups transported, separated by transporter & user.
# Filter this by transport & paginate if you don't wanna get the #whammy when dealing with worst-case data sets.
#
sub list_transported_backups {
    my ( $args, $metadata, $api_args ) = @_;

    my %options = _do_db_pagination( $metadata, $api_args );
    if ( $args->{transport} ) {
        $options{search_field} = 'transport';
        $options{search_term}  = $args->{transport};
    }

    require Cpanel::Backup::Transport::History;
    my $history = Cpanel::Backup::Transport::History->new();
    my $results = $history->get(%options);

    #Choke this list down to transport => user => dates hash
    my $reshash = {};
    foreach my $r (@$results) {
        $reshash->{ $r->{transport} } //= {};
        $reshash->{ $r->{transport} }->{ $r->{user} } //= [];
        push( @{ $reshash->{ $r->{transport} }->{ $r->{user} } }, $r->{date} );
    }

    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';
    return { 'remote_backups' => $reshash };
}

sub get_transport_status {
    my ( $args, $metadata, $api_args ) = @_;

    my %options = _do_db_pagination( $metadata, $api_args );
    if ( $args->{transport_id} ) {
        $options{search_field} = 'transport';
        $options{search_term}  = $args->{transport_id};
    }
    $options{name}  = $args->{transport_name} if $args->{transport_name};
    $options{state} = lc( $args->{state} )    if $args->{state};

    require Cpanel::Backup::Transport::History;
    my $history = Cpanel::Backup::Transport::History->new();
    my ( $results, $pages ) = $history->get_transport_status(%options);

    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';
    return { 'transport_status' => $results, pages => $pages };
}

#
# List all the users *with backup metadata*
#
sub get_users_and_domains_with_backup_metadata {
    my ( $args, $metadata ) = @_;

    # This should never happen - xml-api limits this to callers with root privileges
    die "This can only be invoked by root" unless Whostmgr::ACLS::hasroot();

    require Cpanel::Backup::Metadata;

    my @response_to_caller = Cpanel::Backup::Metadata::get_all_users();

    #Filter by what accounts we actually have
    require Whostmgr::Accounts::List;
    my ( undef, $child_accts ) = Whostmgr::Accounts::List::listaccts();
    my $accounts_to_domains_hr = {
        map { $_->{'user'} => $_->{'domain'} } grep {
            my $subj = $_;
            grep { $_ eq $subj->{user} } @response_to_caller
        } @$child_accts
    };

    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';
    return $accounts_to_domains_hr;
}

sub get_users_with_backup_metadata {
    my $accounts_hr = get_users_and_domains_with_backup_metadata(@_) || {};
    return $_[1]->{'reason'} eq 'OK' ? { 'accounts' => [ sort( keys(%$accounts_hr) ) ] } : undef;
}

sub start_background_pkgacct {
    my ( $args, $metadata ) = @_;

    my $user = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'user' );
    delete $args->{user};

    require Whostmgr::Backup::Pkgacct;
    my $session_info = Whostmgr::Backup::Pkgacct::start_background_pkgacct( $user, $args );

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return $session_info;
}

#
# Queue a restore job to be restored
#
sub restore_queue_add_task {
    my ( $args, $metadata ) = @_;

    my $cli_args = _make_command_line_args($args);

    my $queue_id;
    my @output = _exec_backup_restore_manager( $metadata, 'add', $cli_args );
    return if !@output;

    foreach my $line (@output) {
        if ( $line =~ m/^response:id=(.*)$/ ) {
            $queue_id = $1;
        }
        elsif ( $line =~ m/^metadata:(.*)=(.*)$/ ) {
            $metadata->{$1} = $2;
        }
    }

    return { 'queue_id' => $queue_id };

}

#
# Remove a restore job from the queue
#
sub restore_queue_clear_pending_task {
    my ( $args, $metadata ) = @_;

    my $cli_args = _make_command_line_args($args);

    my @output = _exec_backup_restore_manager( $metadata, 'delete', $cli_args );
    return if !@output;

    foreach my $line (@output) {
        if ( $line =~ m/^metadata:(.*)=(.*)$/ ) {
            $metadata->{$1} = $2;
        }
    }

    return;
}

#
# Remove all restore jobs from the queue
#
sub restore_queue_clear_all_tasks {
    my ( $args, $metadata ) = @_;

    my @output = _exec_backup_restore_manager( $metadata, 'delete_all_regardless' );
    return if !@output;

    foreach my $line (@output) {
        if ( $line =~ m/^metadata:(.*)=(.*)$/ ) {
            $metadata->{$1} = $2;
        }
    }
    return;
}

#
# Remove all restore jobs from the queue
#
sub restore_queue_clear_all_pending_tasks {
    my ( $args, $metadata ) = @_;

    my @output = _exec_backup_restore_manager( $metadata, 'delete_all_pending' );
    return if !@output;

    foreach my $line (@output) {
        if ( $line =~ m/^metadata:(.*)=(.*)$/ ) {
            $metadata->{$1} = $2;
        }
    }
    return;
}

#
# Remove a finished restore job from the finished job list
#
sub restore_queue_clear_completed_task {
    my ( $args, $metadata ) = @_;

    my $cli_args = _make_command_line_args($args);

    my @output = _exec_backup_restore_manager( $metadata, 'delete_finished', $cli_args );
    return if !@output;

    foreach my $line (@output) {
        if ( $line =~ m/^metadata:(.*)=(.*)$/ ) {
            $metadata->{$1} = $2;
        }
    }
    return;
}

#
# Remove all restore jobs from the queue
#
sub restore_queue_clear_all_completed_tasks {
    my ( $args, $metadata ) = @_;

    my @output = _exec_backup_restore_manager( $metadata, 'delete_all_finished' );
    return if !@output;

    foreach my $line (@output) {
        if ( $line =~ m/^metadata:(.*)=(.*)$/ ) {
            $metadata->{$1} = $2;
        }
    }
    return;
}

#
# Remove a all restore job from the queue
#
sub restore_queue_clear_all_failed_tasks {
    my ( $args, $metadata ) = @_;

    my @output = _exec_backup_restore_manager( $metadata, 'delete_all_failed' );
    return if !@output;

    foreach my $line (@output) {
        if ( $line =~ m/^metadata:(.*)=(.*)$/ ) {
            $metadata->{$1} = $2;
        }
    }
    return;
}

#
# List out all the restore jobs in the queue
#
sub restore_queue_list_pending {
    my ( $args, $metadata ) = @_;

    my $restore_job;
    my @output = _exec_backup_restore_manager( $metadata, 'list' );
    return if !@output;

    require Cpanel::SafeStorable;
    foreach my $line (@output) {
        if ( $line =~ m/^response:restore_job=(.*)$/ ) {
            $restore_job = $1;
            $restore_job =~ s/\#\#\#/\n/g;
            $restore_job = Cpanel::SafeStorable::thaw( MIME::Base64::decode_base64($restore_job) );
        }
        elsif ( $line =~ m/^metadata:(.*?)=(.*)$/ ) {
            $metadata->{$1} = $2;
        }
    }
    return { 'restore_job' => $restore_job };
}

#
# List out all the restore jobs being processed
#
sub restore_queue_list_active {
    my ( $args, $metadata ) = @_;

    my $restore_job;
    my @output = _exec_backup_restore_manager( $metadata, 'list_active' );
    return if !@output;

    require Cpanel::SafeStorable;
    foreach my $line (@output) {
        if ( $line =~ m/^response:restore_job=(.*)$/ ) {
            $restore_job = $1;
            $restore_job =~ s/\#\#\#/\n/g;
            $restore_job = Cpanel::SafeStorable::thaw( MIME::Base64::decode_base64($restore_job) );
        }
        elsif ( $line =~ m/^metadata:(.*)=(.*)$/ ) {
            $metadata->{$1} = $2;
        }
    }
    return { 'restore_job' => $restore_job };

}

#
# List out all all states and if a restore is active
#
sub restore_queue_state {
    my ( $args, $metadata ) = @_;

    my $restore_job;
    my @output = _exec_backup_restore_manager( $metadata, 'state' );
    return if !@output;

    my $ret;
    require Cpanel::SafeStorable;
    foreach my $line (@output) {
        if ( $line =~ m/^response:is_active=(.*)$/ ) {
            my $is_active = $1;
            $is_active =~ s/\#\#\#/\n/g;
            $is_active = Cpanel::SafeStorable::thaw( MIME::Base64::decode_base64($is_active) );
            $ret->{'is_active'} = ${$is_active};
        }
        elsif ( $line =~ m/^response:([^=]+)=(.*)$/ ) {
            my $state = $1;
            $restore_job = $2;
            $restore_job =~ s/\#\#\#/\n/g;
            $restore_job = Cpanel::SafeStorable::thaw( MIME::Base64::decode_base64($restore_job) );
            $ret->{$state} = $restore_job;
        }
        elsif ( $line =~ m/^metadata:(.*)=(.*)$/ ) {
            $metadata->{$1} = $2;
        }
    }

    return $ret;

}

#
# List out all the restore jobs being processed
#
sub restore_queue_list_completed {
    my ( $args, $metadata ) = @_;

    my $restore_job;
    my @output = _exec_backup_restore_manager( $metadata, 'list_finished' );
    return if !@output;

    require Cpanel::SafeStorable;
    foreach my $line (@output) {
        if ( $line =~ m/^response:restore_job=(.*)$/ ) {
            $restore_job = $1;
            $restore_job =~ s/\#\#\#/\n/g;
            $restore_job = Cpanel::SafeStorable::thaw( MIME::Base64::decode_base64($restore_job) );
        }
        elsif ( $line =~ m/^metadata:(.*)=(.*)$/ ) {
            $metadata->{$1} = $2;
        }
    }
    return { 'restore_job' => $restore_job };

}

#
# Return boolean reporting whether the queue is being actively processed or not
#

sub restore_queue_is_active {
    my ( $args, $metadata ) = @_;

    my $is_active;
    my @output = _exec_backup_restore_manager( $metadata, 'is_active' );
    return if !@output;

    require Cpanel::SafeStorable;
    foreach my $line (@output) {
        if ( $line =~ m/^response:is_active=(.*)$/ ) {
            $is_active = $1;
            $is_active =~ s/\#\#\#/\n/g;
            $is_active = Cpanel::SafeStorable::thaw( MIME::Base64::decode_base64($is_active) );
        }
        elsif ( $line =~ m/^metadata:(.*)=(.*)$/ ) {
            $metadata->{$1} = $2;
        }
    }
    return { 'is_active' => $is_active && $$is_active };

}

#
# Kick off a process to restore the queued accounts
#
sub restore_queue_activate {
    my ( $args, $metadata ) = @_;

    my @output = _exec_backup_restore_manager( $metadata, 'activate' );
    return if !@output;

    foreach my $line (@output) {
        if ( $line =~ m/^response:ret=(.*)$/ ) {
            my $retval = $1;
        }
        elsif ( $line =~ m/^metadata:(.*)=(.*)$/ ) {
            $metadata->{$1} = $2;
        }
    }
    return;
}

# Toggle user backup setting
sub toggle_user_backup_state {
    my ( $args, $metadata ) = @_;
    my ($user) = map { Whostmgr::API::1::Utils::get_required_argument( $args, $_ ) } qw(
      user
    );
    require Cpanel::Backup::Config;
    my ( $result, $msg ) = Cpanel::Backup::Config::toggle_user_backup_state( $args, $metadata );
    return { 'toggle_status' => $msg };
}

#
# Remove all secret info (passwords, etc.) from a destination config
#
sub _clean_destination_config {
    my ($config) = @_;

    delete $config->{'password'};
    delete $config->{'passphrase'};
    return;
}

sub _make_command_line_args {
    my ($args) = @_;

    my @_pairs   = map { "$_=$args->{$_}" } keys %$args;
    my $cli_args = join( ' ', @_pairs );
    return $cli_args;
}

sub _exec_backup_restore_manager {
    my ( $metadata, $cmd, @args ) = @_;

    my $backup_run = Cpanel::SafeRun::Object->new(
        'program'     => '/usr/local/cpanel/bin/backup_restore_manager',
        'before_exec' => sub {
            Cpanel::CloseFDs::fast_closefds();
            $ENV{'CPANEL'} = 1;
        },
        'args' => [ $cmd, @args ],
    );

    if ( $backup_run->CHILD_ERROR() ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = "Failed to execute /usr/local/cpanel/bin/backup_restore_manager $cmd: " . ( join( q< >, map { $backup_run->$_() // () } qw( autopsy stdout stderr ) ) );
    }
    my $output = $backup_run->stdout();
    return wantarray ? split( m{\n}, $output ) : $output;
}

my $locale;

sub _locale {
    return $locale ||= Cpanel::Locale->get_handle();
}

sub convert_and_migrate_from_legacy_config {
    my ( $args, $metadata ) = @_;
    require Cpanel::Backup::Utility;
    my %opts;
    $opts{'no_convert'} = 1 if exists $args->{'no_convert'} && $args->{'no_convert'} == 1;
    my ( $ret, $msg ) = Cpanel::Backup::Utility::convert_and_migrate_from_legacy_config(%opts);
    $metadata->{'result'} = $ret;
    $metadata->{'reason'} = $msg;
    return;
}

sub fetch_pkgacct_master_log {
    my ( $args, $metadata ) = @_;

    my $session_id = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'session_id' );

    require Whostmgr::Backup::Pkgacct::Logs;
    my $log = Whostmgr::Backup::Pkgacct::Logs::fetch_master_log($session_id);

    $metadata->set_ok();

    return { 'log' => $log };
}

sub get_pkgacct_session_state {

    my ( $args, $metadata ) = @_;

    my $session_id = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'session_id' );

    require Whostmgr::Backup::Pkgacct::State;
    my $state = Whostmgr::Backup::Pkgacct::State::get_pkgacct_session_state($session_id);

    $metadata->set_ok();

    return { 'state' => $state };
}

1;
