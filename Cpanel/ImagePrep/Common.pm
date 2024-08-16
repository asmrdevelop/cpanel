
# cpanel - Cpanel/ImagePrep/Common.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::ImagePrep::Common;

use cPstrict;
use Cpanel::Imports;
use Cpanel::Autodie                 ();
use Cpanel::Exception               ();
use Cpanel::FindBin                 ();
use Cpanel::Logger                  ();
use Cpanel::Services::Enabled       ();
use Cpanel::Time::ISO               ();
use Cpanel::Transaction::File::JSON ();
use Cpanel::SafeRun::Object         ();
use Errno                           ();
use File::Copy::Recursive           ();
use Whostmgr::Services              ();

use Try::Tiny;

=head1 NAME

Cpanel::ImagePrep::Common

=head1 DESCRIPTION

These helpers may be used in subclasses for the purpose of mocking.
If you need similar helpers when implementing new "Task" subclasses,
consider adding those here so they can be shared.

=head1 FUNCTIONS

=head2 new()

Constructor

=cut

sub new { return bless {}, shift }

=head2 quiet()

(Re-)constructor

Adjust a copy of the Common instance so that any run_command or run_command_full
usage refrains from outputting status and stdout/stderr. Returns an instance that
has been adjusted in this way.

  my $common = Cpanel::ImagePrep::Common->new;
  $common->run_command(...);
  $common->quiet->run_command(...); # don't want this particular output
  $common->run_command(...);

=cut

sub quiet {
    my ($self) = @_;
    return bless {
        %$self,
        quiet => 1,
      },
      ref($self);
}

=head2 _unlink()

unlink

Returns true if the file was deleted or already didn't exist; false if the deletion failed.

=cut

sub _unlink {
    my ( $self, $file ) = @_;
    return try {
        if ( Cpanel::Autodie::unlink_if_exists($file) ) {
            $self->regular_logmsg("Deleted '$file'");
        }
        1;
    }
    catch {
        $self->regular_logmsg("Failed to delete '$file': $_");
        0;
    };
}

=head2 _glob()

glob

=cut

sub _glob {
    my ( $self, $pattern ) = @_;
    return glob $pattern;
}

=head2 _getpwnam()

getpwnam

=cut

sub _getpwnam {
    my ( $self, $user ) = @_;
    return getpwnam($user);
}

=head2 _getgrnam()

getgrnam

=cut

sub _getgrnam {
    my ( $self, $group ) = @_;
    return getgrnam($group);
}

=head2 _rename()

rename -- actually uses File::Copy::Recursive::rmove() to support cross-filesystem renames

Returns 1 if the rename was successful or if the origin file did not exist.

Returns 0 if the rename was attempted but failed.

=cut

sub _rename {
    my ( $self, $src, $dest ) = @_;
    if ( !-e $src ) {    # not race safe
        $self->regular_logmsg("$src does not exist");
        return 1;
    }
    $self->regular_logmsg("rename $src -> $dest");
    return File::Copy::Recursive::rmove( $src, $dest );
}

=head2 _exists()

-e

=cut

sub _exists {
    my ( $self, $path ) = @_;
    return -e $path;
}

=head2 _touch()

Touch a file

=cut

sub _touch {
    my ( $self, $path ) = @_;
    $self->regular_logmsg("touch $path");
    open my $fh, '>>', $path or return 0;
    close $fh;
    return 1;
}

=head2 _systemctl()

Run a systemctl command

=cut

my $systemctl_bin;

sub _systemctl {
    my ( $self, @args ) = @_;

    $systemctl_bin ||= Cpanel::FindBin::findbin('systemctl');
    $systemctl_bin || die 'systemctl binary not found';

    return $self->run_command( $systemctl_bin, @args );
}

=head2 _get_unit_property($unit, $property)

Retrieve the systemd unit property from the given unit.
The returned value may be the empty string if the unit or property do not exist.

=cut

sub _get_unit_property {
    my ( $self, $unit, $property ) = @_;
    my $show = $self->quiet->_systemctl( "--property=$property", 'show', $unit )->stdout();
    if ( defined($show) && $show =~ /^[^=]+=(.+)/ ) {    # --value is not supported on all distros
        return $1;
    }
    return q{};
}

=head2 _get_unit_state($unit)

Retrieve the systemd unit state for the given unit.
The returned value may be the empty string if the unit does not exist.

=cut

sub _get_unit_state {
    my ( $self, $unit ) = @_;

    # Sometimes the UnitFileState value is "bad" when a unit is masked, so LoadState is only used to
    # determine if the unit is masked.
    my $loadstate = $self->_get_unit_property( $unit, 'LoadState' );
    if ( $self->_unit_state_is_masked($loadstate) ) {
        return $loadstate;
    }
    return $self->_get_unit_property( $unit, 'UnitFileState' );
}

=head2 _unit_state_is_enabled($state)

Given a systemd UnitFileState value, return true if it is "enabled" or equivalent.

=cut

sub _unit_state_is_enabled {
    my ( $self, $state ) = @_;
    return $state =~ m{^(?:enabled|linked|static)} ? 1 : 0;
}

=head2 _unit_state_is_masked($state)

Given a systemd UnitFileState value, return true if it is "masked" or equivalent.

=cut

sub _unit_state_is_masked {
    my ( $self, $state ) = @_;
    return $state =~ m{^(?:masked)} ? 1 : 0;
}

=head2 _mask_unit($unit)

Attempt to mask the provided systemd unit.

- Returns true if the mask is successful, otherwise false.

=cut

sub _mask_unit {
    my ( $self, $unit ) = @_;

    # Checking the fragment path is only needed to avoid error noise in the log because a
    # mask will fail when units live under /etc/systemd/system.
    my $fragment_path = $self->_get_unit_property( $unit, 'FragmentPath' );
    my $result        = 0;
    if ( index( $fragment_path, '/etc/systemd/system' ) != 0 ) {
        $self->regular_logmsg("Masking the '$unit' unit.");
        $result = try { $self->_systemctl( 'mask', $unit ); 1; } || 0;
    }
    else {
        $self->regular_logmsg("Not attempting to mask the '$unit' unit because it lives under '/etc/systemd/system'.");
    }
    return $result;
}

=head2 _get_service_disable_file($service)

Returns the disable touchfile path that is most likely to work for a given service name.

=cut

sub _get_service_disable_file {
    my ( $self, $service ) = @_;
    return
         $self->_get_unit_disable_file($service)
      || ( Cpanel::Services::Enabled::get_files_for_service($service) || [] )->[0]
      || ( '/etc/' . $service . 'disable' );
}

=head2 _get_unit_disable_file($unit)

Returns the disable touchfile path that will prevent the given systemd unit from starting if one is
defined in the unit configuration.

=cut

sub _get_unit_disable_file {
    my ( $self, $unit ) = @_;

    # This looks like a property but is not available to _get_unit_property()
    my $data = try { $self->quiet->_systemctl( 'cat', $unit )->stdout() };
    if ( defined($data) && $data =~ /^ConditionPathExists=[!](.+disabled?)/m ) {
        return $1;
    }
    return;
}

=head2 run_command( program, arg1, ... )

Shortened version of run_command_full

=cut

sub run_command {
    my ( $self, $program, @args ) = @_;
    for ( $program, @args ) { die if ref }
    return $self->run_command_full(
        program => $program,
        args    => \@args,
        timeout => 14400,      # 4 hours
    );
}

=head2 run_command_full( ... )

Run a command using Cpanel::SafeRun::Object and log the name of
the command and the output to the log.

It accepts key/value pairs with Cpanel::SafeRun::Object parameters.

=cut

sub run_command_full {
    my ( $self, %saferun_obj_args ) = @_;

    $self->regular_logmsg( sprintf( '+ %s %s', $saferun_obj_args{program}, join( ' ', @{ $saferun_obj_args{args} // [] } ) ) );
    my $obj;
    try {
        $obj = Cpanel::SafeRun::Object->new_or_die(
            read_timeout => 3600,    # 1 hour
            %saferun_obj_args
        );
    }
    catch {
        my $exception_string = Cpanel::Exception::get_string($_);
        $self->regular_logmsg( "  (failed)\n" . $exception_string ) if !$self->{quiet};
        die $exception_string . "\n";    # This strips the exception of its objectness, but we almost certainly will be printing/logging rather than catching and handling by type
    };

    if ( !$self->{quiet} ) {
        $self->regular_logmsg('  (succeeded)');

        for my $output (qw(stdout stderr)) {
            next unless $obj->$output;
            chomp( my $msg = "($output) " . $obj->$output );
            $self->raw_logmsg("$msg\n");
        }
    }

    return $obj;
}

sub BACKUP_DIR { return '/var/cpanel/snapshot_prep.backup' }

=head2 _rename_to_backup()

Rename the file or directory to a backup copy.

For example, /var/cpanel/ssl could be renamed to: /var/cpanel/snapshot_prep.backup/2022-05-24T18:25:56Z/:var:cpanel:ssl

- Returns the path to the backup if the operation completed.

- Returns undef if the source file / directory didn't exist.

- Throws an exception if the rename fails.

Note: These backup files cannot be automatically restored. They are
only kept as an extra safeguard against data loss in case the tool
is run someplace where it shouldn't have been.

=cut

my $_DATE;    # Save date per process because more than one Common instance may exist in a process

sub _rename_to_backup {
    my ( $self, $path ) = @_;
    return undef if !$self->_exists($path);

    $_DATE //= Cpanel::Time::ISO::unix2iso();
    my $subdir = sprintf( '%s/%s', BACKUP_DIR, $_DATE );

    Cpanel::Autodie::mkdir_if_not_exists( $_, 0700 ) for BACKUP_DIR, $subdir;

    my $backup = sprintf( '%s/%s', $subdir, $path =~ tr[/][:]r );
    if ( !$self->_rename( $path, $backup ) ) {
        die "Failed to rename $path to $backup: $!\n";
    }

    return $backup;
}

=head2 regular_logmsg($message)

Output a $logger->info() message to the standard logging facility, which produces
terminal output and records the message in /usr/local/cpanel/logs/error_log.

=cut

sub regular_logmsg {
    my ( $self, $message ) = @_;

    $self->{logger} ||= Cpanel::Logger->new(
        {
            use_stdout => 1,    # helps with piping terminal output and also with capturing it in automated tests
        }
    );

    return $self->{logger}->info($message);
}

=head2 warn_logmsg($message)

Output a logger->warn() message to the standard logging facility, which produces
terminal output and records the message in /usr/local/cpanel/logs/error_log.

=cut

sub warn_logmsg {
    my ( $self, $message ) = @_;
    return $self->logger()->warn($message);
}

=head2 raw_logmsg($message)

Output a $logger->raw() message (lacks timestamp and other prefixes) to
/usr/local/cpanel/logs/error_log and duplicate it to stdout.

=cut

sub raw_logmsg {
    my ( $self, $message ) = @_;

    print $message;
    return Cpanel::Logger->new()->raw($message);
}

sub CLOUD_INIT_INSTANCE_SYMLINK { return '/var/lib/cloud/instance' }
sub GCLOUD_INSTANCE_FILE        { return '/etc/default/instance_configs.cfg' }
sub FLAG_DIR                    { return '/var/cpanel/regenerate_tokens' }

=head2 is_cloud()

Returns 1 if this server has a cloud-init instance symlink or the gcloud instance data.
Returns 0 otherwise.

This should not be confused with an "is virtualized" check.

This is_cloud check should be used when deciding whether to perform repair-oriented cleanup,
but not necessarily for the pre- / post- tasks when invoked manually via the scripts. There
may be legitimate reasons to want to use these utilities in environments that we don't
recognize as "cloud."

=cut

sub is_cloud {
    return ( defined instance_id() ? 1 : 0 );
}

=head2 instance_id()

Returns the unique ID of this instance, the string "unknown" if the ID cannot be determined,
or undef if the system is not a cloud instance.

=cut

our $instance_id;

sub instance_id {
    unless ( defined $instance_id ) {
        if ( -l CLOUD_INIT_INSTANCE_SYMLINK ) {
            $instance_id = ( readlink(CLOUD_INIT_INSTANCE_SYMLINK) =~ s{\A.*/}{}r ) || 'unknown';
        }
        elsif ( -e GCLOUD_INSTANCE_FILE && open my $fh, "<", GCLOUD_INSTANCE_FILE ) {
            local $/ = undef;
            my $instance_data = readline($fh);
            close $fh;
            $instance_id = ( $instance_data =~ m{^instance_id += +([0-9]+)$}m )[0] || 'unknown';
        }
    }
    return $instance_id;
}

=head2 disable_service($service)

Given a service name, shut down and disable that service.

The first time this is called for a given service it will record the existing
enabled/disabled state of the service in the datastore so that the C<enable_service>
method will know if it should be enabled again, or not.

=cut

sub disable_service {
    my ( $self, $service ) = @_;

    my $unit_state = $self->_get_unit_state($service);

    # Store the unit state the first time it is seen so enable_service can restore it.
    my $unit_state_key = "service_${service}_unit_state";
    if ( !$self->get_key($unit_state_key) ) {
        $self->store_key( $unit_state_key, $unit_state );
    }

    my $unit_change = 0;
    my $is_enabled  = $self->_unit_state_is_enabled($unit_state);
    my $is_masked   = $self->_unit_state_is_masked($unit_state);

    # Attempting to disable a service while masked will fail
    if ( $is_enabled && !$is_masked ) {
        $unit_change++;
        $self->regular_logmsg("Attempting to disable the '$service' service.");
        $self->_systemctl( 'disable', $service );
    }

    if ( !$is_masked ) {
        $unit_change++;
        $self->regular_logmsg("Attempting to mask the '$service' service.");

        # Some of cPanel & WHM's systemd unit configurations are unmaskable but will respect these
        # touchfiles so they can be used to force a unit not to start.
        if ( my $disable_file = $self->_get_service_disable_file($service) ) {
            $self->_touch($disable_file);
            $self->store_key( "service_${service}_disable_touchfile_created", 1 );
        }

        $self->_mask_unit($service);
    }

    my $is_active = try { $self->quiet->_systemctl( 'is-active', $service ); 1; } || 0;
    if ($is_active) {
        $unit_change++;
        $self->regular_logmsg("Attempting to stop the '$service' service.");
        $self->_systemctl( 'stop', $service );
    }

    if ( !$unit_change ) {
        $self->regular_logmsg("The '$service' service is already disabled.");
    }
    return;
}

=head2 enable_service($service)

Given a service name, enable and start that service if it was previously enabled.

=cut

sub enable_service {
    my ( $self, $service, $opts ) = @_;

    my $force = delete $opts->{'force'};

    my $unit_state_key      = "service_${service}_unit_state";
    my $previous_unit_state = $self->get_key($unit_state_key) // q{};
    if ( !$force && !$previous_unit_state ) {

        # There's nothing that we can safely do here if we don't know the previous service state.
        $self->regular_logmsg("Not enabling the '$service' service because its previous state is unknown.");
        return;
    }

    if ( $self->get_key("service_${service}_disable_touchfile_created")
        && ( my $disable_file = $self->_get_service_disable_file($service) ) ) {
        $self->_unlink($disable_file);
    }

    my $current_unit_state = $self->_get_unit_state($service);
    my $is_masked          = $self->_unit_state_is_masked($current_unit_state);
    my $was_masked         = $self->_unit_state_is_masked($previous_unit_state);
    if ( $is_masked && !$was_masked ) {
        $self->_systemctl( 'unmask', $service );
    }

    my $was_enabled = $self->_unit_state_is_enabled($previous_unit_state);
    if ( $was_enabled || $force ) {
        $self->regular_logmsg( "Enabling and starting the '$service' service." . ( ( $force && !$was_enabled ) ? ' (FORCED)' : '' ) );
        my ($enable_successful) = Whostmgr::Services::enable($service);
        if ( !$enable_successful ) {
            $self->_systemctl( 'enable', '--now', $service );
        }
    }
    else {
        $self->regular_logmsg("Not enabling the '$service' service because it was previously disabled.");
    }
    return;
}

sub DATASTORE_FILE { return '/var/cpanel/.snapshot-datastore.json' }

=head2 save_data($href)

Save the given hashref to the persistent datastore.

This completely overwrites any existing datastore.

=cut

sub save_data {
    my ( $self, $new_hr ) = @_;
    die 'Must provide a hashref' unless ref $new_hr eq 'HASH';
    my $transaction = $self->_get_datastore_transaction();
    $transaction->set_data($new_hr);
    $transaction->save_pretty_canonical_or_die();
    $transaction->close_or_die();
    return;
}

=head2 get_data()

Return a hashref of the persistent datastore.

=cut

sub get_data {
    my ($self) = @_;
    my $data = $self->_get_datastore_transaction->get_data();
    return ref $data eq 'HASH' ? $data : {};
}

=head2 clear_data()

Clear (delete) the persistent datastore.

=cut

sub clear_data {
    my ($self) = @_;
    return $self->_unlink( DATASTORE_FILE() );
}

=head2 store_key($key, $value)

Store the provided key and value in the datastore.
A value can be a scalar, hashref, or arrayref.
Any existing value for the key will be overwritten.

=cut

sub store_key {
    my ( $self, $key, $value ) = @_;
    die 'key must not be a ref' if ref $key;
    die 'key must not be empty' unless length $key;
    my $datastore = $self->get_data();
    $datastore->{$key} = $value;
    return $self->save_data($datastore);
}

sub get_key {
    my ( $self, $key ) = @_;
    return $self->get_data()->{$key};
}

sub _get_datastore_transaction {
    my ($self) = @_;
    return Cpanel::Transaction::File::JSON->new( path => DATASTORE_FILE() );
}

=head2 _sleep($sec)

Sleep for $sec seconds.

=cut

sub _sleep {
    my ( $self, $sec ) = @_;
    return sleep $sec;
}

1;
