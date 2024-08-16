package Cpanel::Backup::Transport;

# cpanel - Cpanel/Backup/Transport.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Try::Tiny;

use Cpanel::Locale           ();
use Cpanel::Transport::Files ();
use Cpanel::Backup::Config   ();
use Cpanel::Hostname         ();
use Cpanel::Rand             ();
use Cpanel::SafeDir::MK      ();
use Cpanel::LoadModule       ();
use Cpanel::YAML::Syck       ();

use constant ID_LENGTH => 24;
our $DESTINATION_DIR = '/var/cpanel/backups';

my $locale;

sub new {
    my ($class) = @_;
    $locale ||= Cpanel::Locale->get_handle();
    my $self = bless {
        'dest_conf_dir' => $DESTINATION_DIR,
        'destinations'  => get_destinations(),
        'error_msg'     => '',
    }, $class;

    return $self;
}

sub check_destination {
    my ( $self, $destination, $disable_on_fail ) = @_;
    my $dest_conf = $self->{'destinations'}->{$destination};

    my $reason;
    my $id   = $dest_conf->{'id'};
    my $type = $dest_conf->{'type'};
    if ( !Cpanel::Transport::Files::is_transport_type_valid($type) ) {
        return ( 0, 'Invalid transport type' );
    }

    # Create a test file for us to upload/download to/from the server
    my $now           = time;
    my $tmpsrcfile    = $DESTINATION_DIR . '/tmp.test.' . $$ . '-' . $now;
    my $tmpverifyfile = $tmpsrcfile . '.copy';
    my $file_contents = "This is a test file created to determine if backups are operable::\n$$\n$now\n";
    if ( open( my $tmp_fh, '>', $tmpsrcfile ) ) {
        print {$tmp_fh} $file_contents;
        close($tmp_fh);
    }
    else {

        # If we can't create the temp file, abort immediately
        return ( 0, $locale->maketext( 'Could not create temp file “[_1]”: [_2]', $tmpsrcfile, $! ) );
    }

    my $retries = get_error_threshold();

    for ( 1 .. $retries ) {
        my $ctf;
        eval { $ctf = Cpanel::Transport::Files->new( $type, $dest_conf ); };

        # If it fails, loop over it three times, if it succeeds, assume it always will.
        if ($@) {
            $reason = parse_exception($@);
            next;
        }

        my $dest_prefix = $ctf->get_path();
        if ($dest_prefix) {    # if we have a path of some sort..
            if ( $dest_prefix !~ m/\/$/ ) {    # ensure the prefix has a slash at the back
                $dest_prefix .= '/';

                # Try to create the path to help ensure it's available
                eval { $ctf->mkdir($dest_prefix); };
                if ($@) {
                    $reason = $locale->maketext( 'Could not create path directory “[_1]”: [_2]', $dest_prefix, parse_exception($@) );
                    next;
                }
            }
        }

        # otherwise it can be relative to where ever the account logs in to
        my $tmpdestfile = $dest_prefix . 'validate.tmp-' . $$ . '-' . $now . '.txt';

        eval { $ctf->put( $tmpsrcfile, $tmpdestfile ); };
        if ($@) {
            $reason = $locale->maketext( 'Could not upload test file: [_1]', parse_exception($@) );
            next;
        }

        # get file back
        eval { $ctf->get( $tmpdestfile, $tmpverifyfile ); };
        if ($@) {
            $reason = $locale->maketext( 'Could not download test file: [_1]', parse_exception($@) );
            next;
        }

        # compare original to the file we uploaded and then downloaded
        if ( open( my $tmp_v_fh, '<', $tmpverifyfile ) ) {
            my $tfile;
            while (<$tmp_v_fh>) {
                $tfile .= $_;
            }
            close($tmp_v_fh);

            if ( defined($tfile) ) {
                if ( $tfile ne $file_contents ) {
                    $reason = $locale->maketext('The downloaded test file is corrupt.');
                    next;
                }
            }
            else {
                $reason = $locale->maketext('The downloaded test file is empty. The remote account possibly exceeded its quota.');
                next;
            }
        }
        else {
            $reason = $locale->maketext( 'Could not open “[_1]” after downloading it.', $tmpverifyfile );
            next;
        }

        eval { $ctf->ls_check($dest_prefix) };
        if ($@) {
            $reason = $locale->maketext( 'Could not list files in destination: [_1]', parse_exception($@) );
            next;
        }

        eval { $ctf->delete($tmpdestfile); };
        if ($@) {
            $reason = $locale->maketext( 'Could not delete the file we had uploaded onto the server: [_1]', parse_exception($@) );
            next;
        }

        # We ran the guantlet
        # No more iterations are needed
        $reason = undef;
        last;
    }

    # If reason is undefined, then we didn't encounter an error
    if ( $disable_on_fail && $reason ) {
        $self->disable_transport( $destination, $reason, 1 );
    }

    unlink $tmpverifyfile if -e $tmpverifyfile;
    unlink $tmpsrcfile    if -e $tmpsrcfile;

    return $reason ? ( 0, $reason ) : ( 1, 'OK' );
}

#
# Take an thrown item and return the message if it is one of our
# transport exceptions.  If it is something else, just return the error
#
sub parse_exception {
    my ($error) = @_;

    if ( ( ref $error ) =~ /^Cpanel::Transport::Exception/ ) {
        return $error->message;
    }
    else {
        return $error;
    }
}

sub get_enabled_destinations {
    my ($self) = @_;
    my %enabled_destinations;

    foreach my $destination ( keys %{ $self->{'destinations'} } ) {
        $enabled_destinations{$destination} = $self->{'destinations'}->{$destination} if !$self->is_disabled($destination);
    }
    return \%enabled_destinations;

}

sub enabled_destination_count {
    my ($self) = @_;
    return scalar keys %{ $self->get_enabled_destinations() };
}

sub get_error_msg {
    my ($self) = @_;
    return $self->{'error_msg'};
}

sub add {
    my ( $self, %OPTS ) = @_;
    $self->{'error_msg'} = '';

    # Generate an id if none set
    unless ( $OPTS{'id'} ) {
        $OPTS{'id'} = _generate_id();
    }

    unless ( _is_id_valid( $OPTS{'id'} ) ) {
        $self->{'error_msg'} = $locale->maketext('Invalid ID provided.');
        return 0;
    }

    my $id = $OPTS{'id'};

    # If it already exists we will need to delete the old
    # file since the name for it may have changed
    if ( exists $self->{'destinations'}->{$id} ) {

        # if delete fails, then pass the error along; but don't invoke cleanup
        $self->delete( $id, 1 ) or return 0;
    }

    # Store and save the backup destination
    my %copy_opts = %OPTS;
    $self->{'destinations'}->{$id} = \%copy_opts;
    $self->_save_transport($id);

    return $id;
}

sub get {
    my ( $self, $id ) = @_;

    $self->{'error_msg'} = '';
    if ( !exists $self->{'destinations'}->{$id} ) {
        $self->{'error_msg'} = $locale->maketext( 'ID “[_1]” does not exist as a destination.', $id );
        return undef;
    }

    # Make a copy so they aren't getting a reference to our
    # internal data structure.
    my %copy = %{ $self->{'destinations'}->{$id} };
    return \%copy;
}

sub delete {
    my ( $self, $id, $no_cleanup ) = @_;
    $self->{'error_msg'} = '';
    if ( !exists $self->{'destinations'}->{$id} ) {
        $self->{'error_msg'} = $locale->maketext( 'ID “[_1]” does not exist as a destination.', $id );
        return 0;
    }

    my $file             = $self->_get_file_path($id);
    my $config_to_delete = delete $self->{'destinations'}->{$id};

    if ( unlink $file ) {

        # Perform any necessary cleanup, but without throwing an error,
        # since we could be deleting it due to being malformed.
        if ( !$no_cleanup ) {
            eval {
                my $type = 'Cpanel::Transport::Files::' . $config_to_delete->{'type'};
                if ( $type->can('_post_deletion_cleanup') ) {
                    $type->_post_deletion_cleanup($config_to_delete);
                }
            };
        }
        return 1;
    }
    else {
        $self->{'error_msg'} = $locale->maketext( 'Error deleting “[_1]”: [_2]', $file, $! );
        return 0;
    }
}

sub is_disabled {
    my ( $self, $id ) = @_;
    if ( exists $self->{'destinations'}->{$id} && $self->{'destinations'}->{$id}->{'disabled'} ) {
        return 1;
    }
    return 0;
}

sub disable_transport {
    my ( $self, $id, $reason, $no_email ) = @_;

    # Don't disable if already disabled
    return if $self->is_disabled($id);

    $self->{'destinations'}->{$id}->{'disabled'}       = 1;
    $self->{'destinations'}->{$id}->{'disable_reason'} = parse_exception($reason);
    $self->_save_transport($id);

    # Send message to the admin that we have disabled this
    unless ($no_email) {
        send_disabled_message(
            'name'        => $self->{'destinations'}->{$id}->{'name'},
            'type'        => $self->{'destinations'}->{$id}->{'type'},
            'remote_host' => $self->{'destinations'}->{$id}->{'host'},
            'reason'      => $reason
        );
    }
    return;
}

#
# Send a message to the admin that a destination has been disabled
#
# This requires the following named parameters:
#   name, type, remote_host, & reason
#
sub send_disabled_message {
    my %params = @_;

    if ( try { Cpanel::LoadModule::load_perl_module('Cpanel::iContact::Class::Backup::Disabled') } ) {
        require Cpanel::Notify;
        Cpanel::Notify::notification_class(
            'class'            => 'Backup::Disabled',
            'application'      => 'Backup::Disabled',
            'constructor_args' => [
                'origin'      => 'cPanel Backup System',
                'name'        => $params{'name'},
                'type'        => $params{'type'},
                'remote_host' => $params{'remote_host'},
                'reason'      => $params{'reason'}
            ]
        );
    }
    else {
        require Cpanel::iContact;
        $locale ||= Cpanel::Locale->get_handle();

        my $host = Cpanel::Hostname::gethostname();

        my $l_transportdisabled = $locale->maketext('Transport Disabled');
        my $l_name              = $locale->maketext('Name');
        my $l_type              = $locale->maketext('Type');
        my $l_remote_host       = $locale->maketext('Remote Host');
        my $l_reason            = $locale->maketext('Reason');

        my $msg = <<"EOM";
+===================================+
| $l_transportdisabled               |
+===================================+
| $l_name:         $params{'name'}
| $l_type:         $params{'type'}
| $l_remote_host:  $params{'remote_host'}
|
| $l_reason:       $params{'reason'}
+===================================+
EOM

        my $subject = $locale->maketext( 'Backup destination “[_1]” has been disabled on “[_2]”.', $params{'name'}, $host );

        Cpanel::iContact::icontact(
            'application' => 'cpbackupdisabled',
            'subject'     => $subject,
            'message'     => $msg,
        );
    }

    return;
}

sub ob_string {
    my ($str) = @_;
    if ( !$str ) { return; }
    my $ob = pack( "u", ( $str ^ '+' x ( length($str) ) ) );
    $ob =~ s/([\r\n])//g;
    return $ob;
}

sub deob_string {
    my ($obbed) = @_;
    if ( !$obbed ) { return; }
    my $what = unpack( chr( ord('a') + 20 ), $obbed );
    if ( !$what ) { return; }    # in case it was some fubar data, or someone tried to type the pass in to the config directly
    return $what ^ '+' x ( length($what) );
}

sub _save_transport {
    my ( $self, $id ) = @_;

    # alias
    my $transport = $self->{'destinations'}->{$id};

    if ( !defined $transport || !defined( $transport->{'name'} ) ) {
        print "Skipping saving of bunk destination $id\n";
        return;
    }
    my $destination_file = $self->_get_file_path($id);
    foreach my $to_ob ( 'password', 'passphrase' ) {
        my $is_ob = $to_ob . '_is_ob';
        next unless exists( $transport->{$to_ob} ) && !$transport->{$is_ob};
        $transport->{$to_ob} = Cpanel::Backup::Transport::ob_string( $transport->{$to_ob} );
        $transport->{$is_ob} = 1;                                                              # flag it ( in memory ) to avoid a double ob call
    }
    my $unblessed_hash_ref = _clean_transport($transport);
    YAML::Syck::DumpFile( $destination_file, $unblessed_hash_ref );
    chmod 0600, $destination_file;
    return;
}

# Clean up destination for saving back to config file to prevent fatal corruption.
sub _clean_transport {
    my $transport = shift;
    if ( exists( $transport->{'disable_reason'} ) ) {
        $transport->{'disable_reason'} =~ s/([\r\n])//g;
    }

    # delete $transport->{'sessions'};
    delete $transport->{'config'};
    delete $transport->{'ftp_obj'};
    delete $transport->{'sftp_obj'};
    delete $transport->{'rsync_obj'};
    delete $transport->{'bucket_obj'};
    delete $transport->{'s3'};
    delete $transport->{'dav'};
    delete $transport->{'ns'};

    fix_upload_system_backup($transport);
    fix_only_used_for_logs($transport);

    # Some transports at certain times will try to save this as a blessed hash, so in lieu of curse() or debless() or something, we just copy it.
    my %unblessed_hash = %{$transport};

    # delete these informations from the clean object only
    delete @unblessed_hash{qw(password_is_ob passphrase_is_ob)};

    return \%unblessed_hash;
}

#
# Force upload_system_backup to be 0/1
# Values such as "off" and "false" should be turned into 0
#
sub fix_upload_system_backup {
    my ($transport) = @_;

    if ( exists( $transport->{'upload_system_backup'} ) ) {
        if ( $transport->{'upload_system_backup'} =~ /false|off/i ) {
            $transport->{'upload_system_backup'} = 0;
        }
        if ( $transport->{'upload_system_backup'} ) {
            $transport->{'upload_system_backup'} = 1;
        }
    }

    return;
}

#
# Force only_used_for_logs to be 0/1
# Values such as "off" and "false" should be turned into 0
#
sub fix_only_used_for_logs {
    my ($transport) = @_;

    if ( exists( $transport->{'only_used_for_logs'} ) ) {
        if ( $transport->{'only_used_for_logs'} =~ /false|off/i ) {
            $transport->{'only_used_for_logs'} = 0;
        }
        if ( $transport->{'only_used_for_logs'} ) {
            $transport->{'only_used_for_logs'} = 1;
        }
    }
    else {    # Make sure this exists, default to off
        $transport->{'only_used_for_logs'} = 0;
    }

    return;
}

sub _load_transport {
    my ($destination_path) = @_;
    my $transport_cfg;
    $transport_cfg = YAML::Syck::LoadFile($destination_path) if -e $destination_path;
    if ( exists( $transport_cfg->{'password'} ) ) {
        $transport_cfg->{'password'} = Cpanel::Backup::Transport::deob_string( $transport_cfg->{'password'} );
        delete $transport_cfg->{'password_is_ob'};
    }
    if ( exists( $transport_cfg->{'passphrase'} ) ) {
        $transport_cfg->{'passphrase'} = Cpanel::Backup::Transport::deob_string( $transport_cfg->{'passphrase'} );
        delete $transport_cfg->{'passphrase_is_ob'};
    }
    fix_upload_system_backup($transport_cfg);
    fix_only_used_for_logs($transport_cfg);
    return $transport_cfg;
}

# Helper methods ( used by the constructor)
sub get_destinations {
    my %destinations;

    Cpanel::SafeDir::MK::safemkdir($DESTINATION_DIR) if !-d $DESTINATION_DIR;

    if ( opendir( my $dest_dh, $DESTINATION_DIR ) ) {
        foreach my $destination_file ( readdir($dest_dh) ) {
            next if $destination_file =~ /^\.{1,2}$/;

            my $id = _get_id_from_filename($destination_file);
            next unless $id;

            my $destination_path = $DESTINATION_DIR . '/' . $destination_file;
            next if -d $destination_path;

            my $dest_config = _load_transport($destination_path);
            next unless is_valid_config($dest_config);

            $destinations{$id} = $dest_config;
        }
    }
    return \%destinations;
}

#
# This normalizes certain boolean values in the destinations
# so as to be compatible with the front-end
# We won't need this anymore when we standardize our bool
# representations.
#
sub get_destinations_bool_normalized {

    my @binary_params = qw|ssl mount no_mount_fail passive|;

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

    return \@result_list;
}

# Stub for now, but will eventually validate that all values are in place
sub is_valid_config {
    my ($config) = @_;
    if ( !Cpanel::Transport::Files::is_transport_type_valid( $config->{'type'} ) ) {
        return 0;
    }
    return exists $config->{'type'};
}

#
# Remove all secret info (passwords, etc.) from a destination config
#
sub _clean_destination_config {
    my ($config) = @_;

    delete @{$config}{qw{password passphrase password_is_ob passphrase_is_ob}};

    return;
}

#
# This will hold our prefered method for generating unique id's
#
sub _generate_id {
    my $id = Cpanel::Rand::api2_getranddata( length => ID_LENGTH );

    return $id->{'random'};
}

#
# Test if an ID is valid
#
sub _is_id_valid {
    my ($id) = @_;

    return ( length($id) == ID_LENGTH );
}

sub _get_file_path {
    my ( $self, $id ) = @_;

    my $name = $self->{'destinations'}->{$id}->{'name'};
    $name =~ s|\W|_|g;
    $name = substr( $name, 0, 24 ) if length($name) > 24;
    $name .= '_UID_' . $id . '.backup_destination';

    return $DESTINATION_DIR . '/' . $name;
}

sub _get_id_from_filename {
    my ($filename) = @_;

    my $id_len = ID_LENGTH;
    if ( $filename =~ m|^.*_UID_(.{$id_len})\.backup_destination$| ) {
        return $1;
    }

    # Invalid file name
    return undef;
}

sub get_timeout {
    my ( $self, $id ) = @_;

    return 0 unless defined $self->{'destinations'}{$id}{'timeout'};

    return $self->{'destinations'}{$id}{'timeout'};
}

sub validate_transport {
    my ( $args, $metadata, $dest_obj ) = @_;
    my ( $result, $msg );

    try {

        my $timeout = $dest_obj->get_timeout( $args->{'id'} );
        $timeout ||= 30;

        # The code we are about to call contains eval blocks which, in turn,
        # calls other code containing eval blocks.  It's evals all the way down.
        # So, we need to keep sending the alarm signal & "dying" until
        # control bubbles up to the catch block below.
        local $SIG{'ALRM'} = sub { alarm 1; die "Timeout\n"; };
        alarm $timeout;

        ( $result, $msg ) = $dest_obj->check_destination( $args->{'id'}, $args->{'disableonfail'} );

        alarm 0;
    }
    catch {

        # Turn off the last remaining alarm set by our alarm signal handler
        alarm 0;

        $result = 0;
        $msg    = $_;
    };

    if ( $result == 1 ) {
        $metadata->{'result'} = 1;
        $metadata->{'reason'} = 'OK';
    }
    else {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $locale->maketext( 'Validation for transport “[_1]” failed: [_2]', $args->{'name'}, $msg );
    }
    return;
}

sub validate_common {
    my ( $args, $metadata ) = @_;
    $locale ||= Cpanel::Locale->get_handle();

    my $type = $args->{'type'};

    # Validate the type
    if ( !Cpanel::Transport::Files::is_transport_type_valid($type) ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $locale->maketext( 'The backup destination type is invalid: [_1]', $type );
        return 0;
    }

    # Test all of our params
    my @missing = Cpanel::Transport::Files::missing_parameters( $type, $args );
    if (@missing) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $locale->maketext( 'The following parameters were missing: [list_and,_1]', \@missing );
        return 0;
    }

    # Test all of our params
    my @invalid = Cpanel::Transport::Files::validate_parameters( $type, $args );
    if (@invalid) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $locale->maketext( 'The following parameters were invalid: [list_and,_1]', \@invalid );
        return 0;
    }
    return 1;
}

#
# This is the number of retries to do before failing
#
sub get_error_threshold {
    my $conf_ref = Cpanel::Backup::Config::load();
    return $$conf_ref{'ERRORTHRESHHOLD'} || 3;
}

1;
