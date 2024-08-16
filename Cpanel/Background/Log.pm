
# cpanel - Cpanel/Background/Log.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Background::Log;

use strict;
use warnings;

use Cpanel::Autodie                        ();
use Cpanel::JSON                           ();
use Cpanel::PwCache                        ();
use Cpanel::SafeDir::MK                    ();
use Cpanel::Background::Log::Frame         ();
use Cpanel::Background::Log::NameGenerator ();

=head1 MODULE

C<Cpanel::Background::Log>

=head1 DESCRIPTION

C<Cpanel::Background::Log> provides a log file writer to record events
as JSON entries. Each line of data written is a complete event encoded
as JSON. You can package any arbitrary data with each message, but the
data must be serializable as JSON.

You can only deserialize() the data after the log is closed via the close()
method.

=head1 SYNOPSIS

 my $log = Cpanel::Background::Log->new({ path => /home/cpuser/bglog });
 $log->debug('step', { description => "Reached step 1", step => 1 });
 $log->info('create_db', { description => "Created the 'db1'." });
 $log->warn('limit_exceeded', { description => "You exceeded the disk quota by doing a thing.", quota => 100000, overage => 250000 });
 $log->error('exception', { description => "Could not read the file." });
 $log->done('backup_complete');

 $log->close();

 my $data = $log->deserialize();
 foreach my $msg (@$data) {
    print 'Error: ' . $msg->{data}{description} if $msg->{type} eq 'error';
    print 'Warning: ' . $msg->{data}{description} if $msg->{type} eq 'warn';
    print 'Info: ' . $msg->{data}{description} if $msg->{type} eq 'info';
    print 'Process Complete' if ($msg->{type} eq 'done');
 }

=head1 CONSTRUCTORS

=head2 new()

=head3 ARGUMENTS

=over

=item path - string

Base path where the logs are written.

=item log - string

Custom log name. If not provided a log name
will be generated based on the current date/time
with the .log extension similar to the following:

  2019-08-05T10:22:22.1.log

If you are opening a log that already exists, just provide
the log parameter.

=back

=cut

sub new {
    my ( $class, $args ) = @_;

    my $self = { ( $args && ref $args eq 'HASH' ? %$args : () ) };
    if ( !defined $args->{path} ) {
        $self->{path} = _get_homedir() . "/.cpanel/logs";
    }
    bless $self, $class;

    $self->_init();

    return $self;
}

=head2 INSTANCE->_init()

Initialize the class and some of the classes dependencies.

=head3 ARGUMENTS

=over

=item self - current instance

=back

=head3 RETURNS

1 on success

=head3 THROWS

=over

=item When the directory can not be created.

=item When an available filename can not be calculated.

=item When the log file can not be opened.

=back

=cut

sub _init {
    my ($self) = @_;
    Cpanel::SafeDir::MK::safemkdir( $self->{path} ) if !-d $self->{path};
    if ( !defined $self->{log} ) {
        ( $self->{log} ) = Cpanel::Background::Log::NameGenerator::get_available_filename_or_die( $self->{path} );
    }

    Cpanel::Autodie::open( $self->{fh}, '>>', $self->path() );
    return 1;
}

=head1 PROPERTIES

=head2 INSTANCE->path - string

Full path to the log file.

=cut

sub path {
    my $self = shift;
    return "$self->{path}/$self->{log}";
}

=head2 INSTANCE->data - string

Getter/setter for custom data appended to each message. This will be merged with
any other custom data passed to the write methods.

=head3 ARGUMENTS

=over

=item NAME - string

Name of the data field.

=item VALUE - any

=back

=cut

sub data {
    my ( $self, $name, $value ) = @_;
    $self->{data}{$name} = $value if defined $value;
    return $self->{data}{$name} if defined $name;
    return { %{ $self->{data} } };
}

=head2 INSTANCE->remove_data(NAME)

Removes a data field from the data collection by field name.

=head3 ARGUMENTS

=over

=item NAME - string

The name of the field to remove from the common data logged with each entry.

=back

=cut

sub remove_data {
    my ( $self, $name ) = @_;
    return delete $self->{data}{$name};
}

=head2 INSTANCE->id - string

Unique identifier for the run the log is monitoring.

=cut

sub id {
    my $self = shift;
    my $id   = $self->{log};
    $id =~ s/\.log$//;
    return $id;
}

=head1 FUNCTIONS

=head2 INSTANCE->debug(NAME, DATA)

Log a debug event.

=head3 ARGUMENTS

=over

=item NAME - string

Unique event name.

=item DATA - Any

Optional data to attach to the message. Usually it's a hashref with other fields.

=back

=cut

sub debug {
    my ( $self, $name, $data ) = @_;
    return $self->write( 'debug', $name, $data );
}

=head2 INSTANCE->info(NAME, DATA)

Log a information event.

=head3 ARGUMENTS

=over

=item NAME - string

Unique event name.

=item DATA - Any

Optional data to attach to the message. Usually it's a hash with other fields.

=back

=cut

sub info {
    my ( $self, $name, $data ) = @_;
    return $self->write( 'info', $name, $data );
}

=head2 INSTANCE->warn(NAME, DATA)

Log a warning event.

=head3 ARGUMENTS

=over

=item NAME - string

Unique event name.

=item DATA - Any

Optional data to attach to the message. Usually it's a hash with other fields.

=back

=cut

sub warn {
    my ( $self, $name, $data ) = @_;
    return $self->write( 'warn', $name, $data );
}

=head2 INSTANCE->error(NAME, DATA)

Log a error event.

=head3 ARGUMENTS

=over

=item NAME - string

Unique event name.

=item DATA - Any

Optional data to attach to the message. Usually it's a hash with other fields.

=back

=cut

sub error {
    my ( $self, $name, $data ) = @_;
    return $self->write( 'error', $name, $data );
}

=head2 INSTANCE->done(NAME, DATA)

Log a done event.

=head3 ARGUMENTS

=over

=item NAME - string

Unique event name.

=item DATA - Any

Optional data to attach to the message. Usually it's a hash with other fields.

=back

=cut

sub done {
    my ( $self, $name, $data ) = @_;
    return $self->write( 'done', $name, $data );
}

=head2 INSTANCE->close()

Close the log file if its open.

=cut

sub close {
    my ($self) = @_;
    if ( $self->{fh} ) {
        $self->write('close');
        Cpanel::Autodie::close( $self->{fh} );
        delete $self->{fh};
        $self->{closed} = 1;
    }
    return 1;
}

=head2 INSTANCE->is_open

Check if the object thinks the logfile is open.

=head3 RETURNS

Boolean - 1 when the log is open, 0 otherwise.

=cut

sub is_open {
    my ($self) = @_;
    return defined $self->{fh} ? 1 : 0;
}

=head2 INSTANCE->write(TYPE, NAME, DATA) [PRIVATE]

Helper to write a line to the logfile.

=cut

sub write {
    my ( $self, $type, $name, $data ) = @_;

    if ( $self->{closed} || !$self->{fh} || !_writeable( $self->{fh} ) ) {
        die "Log closed already: $type $name " . ( $data && $data->{description} ? $data->{description} : '' );
    }

    my $frame = Cpanel::Background::Log::Frame->new( type => $type, name => $name, data => $self->{data} );
    $frame->merge_data($data);
    $self->write_raw( $frame->serialize() );
    return;
}

# For Jenkins... :( -- see HB-5131 notes
sub _writeable {
    return -w $_[0];
}

=head2 INSTANCE->write_raw(TEXT) [PRIVATE]

Helper to write a line to the logfile.

=cut

sub write_raw {
    my ( $self, $frame_serialized ) = @_;
    print { $self->{fh} } $frame_serialized;
    flush { $self->{fh} };
    return;
}

=head2 INSTANCE->deserialize()

Parse the log file into a Perl object

=head3 RETURNS

Arrayref with hashrefs for each line of the log file.

Each hash will have the following structure:

=over

=item type - string

One of:

=over

=item * debug

=item * info

=item * warn

=item * error

=item * done

=back

=item name - string

Optional event name.

=item data - any

Optional data associated with the logged event.

=back

=cut

sub deserialize {
    my ($self) = @_;
    die 'Not done writing the log. Close the log before trying to deserialize.' if $self->is_open();

    my @lines = $self->_get_entries();

    # The lines are encoded JSON fragments
    # We assemble them into a single JSON array before parsing.
    my $json = '[' . join( ',', @lines ) . ']';
    return Cpanel::JSON::Load($json);
}

=head2 INSTANCE->_get_entries() [PRIVATE]

Fetch a list of the raw log lines.

=head2 RETURNS

List of JSON encoded lines from the log.

=cut

sub _get_entries {
    my ($self) = @_;
    if ( !$self->{all_entries} ) {
        Cpanel::Autodie::open( my $fh, '<', $self->path() );
        my @lines = <$fh>;
        chomp @lines;
        $self->{all_entries} = \@lines;
        Cpanel::Autodie::close($fh);
    }
    return @{ $self->{all_entries} };
}

=head2 INSTANCE->has_entries_of_type(TYPE)

Checks if the collection has entries of the specified type.

=head3 ARGUMENTS

=over

=item TYPE - string

One of the following:

=over

=item * debug

=item * info

=item * warn

=item * error

=item * done

=back

=back

=head3 RETURNS

1 if the log contains entries of the type, 0 otherwise.

=cut

sub has_entries_of_type {
    my ( $self, $type ) = @_;
    my $lines = $self->deserialize();
    require List::Util;
    return ( List::Util::first { $_->{type} eq $type } @$lines ) ? 1 : 0;
}

=head2 INSTANCE->get_entries_by_type(TYPE)

Helper to get a list of the log entries of a given type.

=head3 ARGUMENTS

=over

=item TYPE - string

One of the following:

=over

=item * debug

=item * info

=item * warn

=item * error

=item * done

=back

=back

=head3 RETURNS

List of deserialized log entries with the specified type.

=cut

sub get_entries_by_type {
    my ( $self, $type ) = @_;
    my $lines = $self->deserialize();
    return grep { $_->{type} eq $type } @$lines;
}

=head2 INSTANCE->is_done()

Checks if the process being logged includes a done event.

B<Note> There can be more then one 'done' event in a log. Use
C<is_closed> to see if the running process has completed
processing.

B<Note>: 'done' events may not be present if there were errors
in one of the processing being logged.

=head2 RETURNS

1 if a done entry is present

=cut

sub is_done {
    my ($self) = @_;
    my @lines = $self->get_entries_by_type('done');
    return @lines ? 1 : 0;
}

=head2 INSTANCE->is_closed()

Checks if the process being logged has completed all its steps.

=head2 RETURNS

1 if a 'close' entry is present, 0 otherwise.

=cut

sub is_closed {
    my ($self) = @_;
    my @lines = $self->get_entries_by_type('close');
    return @lines ? 1 : 0;
}

=head2 _get_homedir [PRIVATE]

Helper method to get the current user's home directory.

=head3 RETURNS

string - the current user's home path

=cut

sub _get_homedir {
    return $Cpanel::homedir // Cpanel::PwCache::gethomedir($>);
}

1;
