package Cpanel::ProcessLog;

# cpanel - Cpanel/ProcessLog.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Try::Tiny;

use Cpanel::Autodie            ();
use Cpanel::Fcntl              ();
use Cpanel::FHUtils::Autoflush ();
use Cpanel::Mkdir              ();

=encoding utf-8

=head1 NAME

Cpanel::ProcessLog - Framework for recording a process’s output and exit.

=head1 SYNOPSIS

    package My::Log;

    use constant _DIR => '/path/to/logs';

    package main;

    my $log_id = My::Log->create_new(
        'some-description',
        @metadata_kv,
    );

    my $metadata_hr = My::Log->get_metadata('some-description');

    My::Log->set_metadata( 'some-description', CHILD_ERROR => 0 );

    My::Log->redirect_stdout_and_stderr('some-description');

    my $read_fh = My::Log->open('some-description');

=head1 DESCRIPTION

This module is a generalization of the logging logic originally implemented
in L<Cpanel::Plugins::Log>. It’s useful in contexts where we want to report
a process’s output as well as its exit state.

There is an
attempt to abstract away the storage details, though it’s a fairly weak
abstraction.

An individual log instance is referred to as a log “instance”.

=head1 METADATA

This framework provides the ability to store metadata along with the log
itself. The metadata are simple key/value pairs, subject to the following
restrictions:

=over

=item * Keys must be safe to be filesystem nodes.

=item * Values must be nonempty and must not exceed the length limit
for a filesystem symbolic link.

=back

=head1 TODO

Reduce duplication between here and Cpanel::SSL::Auto::Log.

#----------------------------------------------------------------------

=head1 SUBCLASS INTERFACE

Define the following to create a functional subclass of this module:

=head2 $DIR = I<CLASS>->_DIR()

The parent directory that will store each log instance.

=head2 ($LOG_ID, %METADATA) = I<CLASS>->_new_log_id_and_metadata( @ARGS );

@ARGS are the parameters given to C<new()>. The return should be a new
instance’s LOG_ID as well as whatever metadata keys/values should be created
as part of creation of the log instance.

Note that $LOG_ID B<must> be a valid filesystem node name.

=head2 @METADATA_KEYS = I<CLASS>->_METADATA_SCHEMA()

Optional. This returns a list of metadata keys (i.e., names).

For example, if you’re
monitoring a non-Perl process and want to record the process’s exit value,
you might make C<CHILD_ERROR> one of the metadata keys.

On the other hand,
if success/failure is all you care about (e.g., if the log itself will show
any relevant failure details), a simple C<SUCCESS> boolean may suffice.

The default is empty.

=cut

use constant _METADATA_SCHEMA => ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=cut

use constant _FORMAT_EXTENSION => 'txt';

#----------------------------------------------------------------------

=head2 $LOG_ID = I<CLASS>->create_new( @ARGS )

Creates a new log instance. @ARGS are passed to the subclass’s
C<_new_log_id_and_metadata()> method to determine that function’s return
values.

If there are metadata keys that the return of C<_new_log_id_and_metadata()>
does not include, those keys’ values will be set to C<?>.

The return is the new instance’s LOG_ID.
LOG_ID is a unique ID to describe this new log.
(If there’s already a log that uses the given LOG_ID, an error is thrown.)

=cut

sub create_new {
    my ( $class, @args ) = @_;

    my ( $reldir, %values ) = $class->_new_log_id_and_metadata(@args);

    #Prefix this onto the name while we’re preparing the directory.
    my $filename_prefix = rand . '.';

    my $pfx_reldir = $filename_prefix . $reldir;

    #First create the directory.
    Cpanel::Mkdir::ensure_directory_existence_and_mode(
        $class->_DIR() . "/$pfx_reldir",
        0700,
    );

    $class->_iterate_schema(
        sub {
            my ($key) = @_;

            my $val = $values{$key};
            $val = '?' if !length $val;

            Cpanel::Autodie::symlink( $val, $class->_DIR() . "/$pfx_reldir/$key" );
        }
    );

    my $wfh;

    Cpanel::Autodie::sysopen(
        $wfh,
        $class->_get_path_to_log($pfx_reldir),
        Cpanel::Fcntl::or_flags(qw(O_EXCL O_CREAT)),
        0600,
    );

    #We created the directory as a temp directory; now that it’s
    #all set up correctly, move it into place.
    Cpanel::Autodie::rename(
        $class->_DIR() . "/$pfx_reldir",
        $class->_DIR() . "/$reldir",
    );

    return $reldir;
}

#----------------------------------------------------------------------

=head2 $metadata_hr = I<CLASS>->get_metadata( LOG_ID )

Returns the log instance’s metadata as a hash reference.

=cut

sub get_metadata {
    my ( $class, $reldir ) = @_;

    die "Need relative dir!" if !$reldir;

    my @keys = $class->_METADATA_SCHEMA();

    my %hash;
    $hash{$_} = Cpanel::Autodie::readlink( $class->_DIR() . "/$reldir/$_" ) for @keys;

    return \%hash;
}

#----------------------------------------------------------------------

=head2 $metadata_hr = I<CLASS>->set_metadata( LOG_ID, %OPTS )

Sets the log instance’s metadata from %OPTS. Only those entries in %OPTS
that match the class’s metadata schema are accepted; others are ignored.

=cut

sub set_metadata {
    my ( $class, $reldir, %new_values ) = @_;

    die "Need relative dir!"    if !$reldir;
    die "Need key/value pairs!" if !%new_values;

    $class->_iterate_schema(
        sub {
            my ($k) = @_;

            if ( exists $new_values{$k} ) {
                my $target_path = $class->_DIR() . "/$reldir/$k";
                my $temp_path   = "$target_path." . rand;

                Cpanel::Autodie::symlink( $new_values{$k}, $temp_path );
                Cpanel::Autodie::rename( $temp_path => $target_path );
            }
        }
    );

    return;
}

#----------------------------------------------------------------------

=head2 I<CLASS>->redirect_stdout_and_stderr( LOG_ID )

Sets the global STDOUT and STDERR filehandles to append to the log
indicated by LOG_ID, and sets those filehandles to autoflush mode.

Call this at the beginning of a log process.

=cut

sub redirect_stdout_and_stderr {
    my ( $class, $reldir ) = @_;

    my $path = $class->_get_path_to_log($reldir);

    Cpanel::Autodie::open( \*STDOUT, '>>',   $path );
    Cpanel::Autodie::open( \*STDERR, '>>&=', \*STDOUT );

    Cpanel::FHUtils::Autoflush::enable($_) for ( \*STDOUT, \*STDERR );

    return;
}

#----------------------------------------------------------------------

=head2 $read_fh = I<CLASS>->open( LOG_ID )

Opens a filehandle to a stored log, as referred to by LOG_ID.

=cut

sub open {
    my ( $class, $reldir ) = @_;

    my $path = $class->_get_path_to_log($reldir);

    Cpanel::Autodie::open( my $rfh, '<', $path );

    return $rfh;
}

#----------------------------------------------------------------------

=head2 $wd = I<CLASS>->inotify_add_log( LOG_ID, INOTIFY_OBJ, @INFY_ADD_ARGS )

Adds a stored log to a given L<Cpanel::Inotify> instance.
@INFY_ADD_ARGS are the arguments
that will be passed to the L<Cpanel::Inotify> instance’s C<add()>
method after the filesystem path.

The idea is to preserve the filesystem paths as an abstraction.

The return value is a watch descriptor, as C<Cpanel::Inotify::add()>
returns.

=cut

sub inotify_add_log {
    my ( $class, $reldir, $inotify_obj, @inotify_args ) = @_;

    die "Need relative dir!" if !$reldir;

    if ( !try { $inotify_obj->isa('Cpanel::Inotify') } ) {
        die "Must be Cpanel::Inotify instance, not “$inotify_obj”!";
    }

    return $inotify_obj->add(
        $class->_get_path_to_log($reldir),
        @inotify_args,
    );
}

#----------------------------------------------------------------------

=head2 $wd = I<CLASS>->inotify_add_metadata( LOG_ID, INOTIFY_OBJ )

Like C<inotify_add_log()>, but
adds the metadata container to a given L<Cpanel::Inotify> instance
rather than the log file.

Also, no flags are accepted because,
by design, the inotify flags C<CREATE> and C<MOVED_TO> are the only
ones we’ll care about.

=cut

sub inotify_add_metadata {
    my ( $class, $reldir, $inotify_obj ) = @_;

    die "Need relative dir!" if !$reldir;

    if ( !try { $inotify_obj->isa('Cpanel::Inotify') } ) {
        die "Must be Cpanel::Inotify instance, not “$inotify_obj”!";
    }

    return $inotify_obj->add(
        $class->_DIR() . "/$reldir",
        flags => [ 'ONLYDIR', 'DONT_FOLLOW', 'CREATE', 'MOVED_TO' ],
    );
}

#----------------------------------------------------------------------

sub _get_path_to_log {
    my ( $class, $reldir ) = @_;

    die "Need log ID!" if !length $reldir;

    return $class->_DIR() . "/$reldir/" . _FORMAT_EXTENSION();
}

sub _iterate_schema {
    my ( $class, $todo_cr ) = @_;

    $todo_cr->($_) for $class->_METADATA_SCHEMA();

    return;
}

1;
