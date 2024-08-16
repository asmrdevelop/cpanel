# cpanel - Cpanel/Server/Downloads/Backups/MySql.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Server::Downloads::MySqlBackup;

use cPstrict;

use parent qw(Cpanel::Server::Downloads::Base);

use Cpanel::AdminBin::Call           ();
use Cpanel::Config::Constants::MySQL ();
use Cpanel::Encoder::URI             ();
use Cpanel::Exception                ();
use Cpanel::FastSpawn::InOut         ();

use Cpanel::Imports;

=head1 MODULE

C<Cpanel::Server::Downloads::MySqlBackup.pm>

=head1 DESCRIPTION

C<Cpanel::Server::Downloads::MySqlBackup.pm> provides a C<Cpanel::Handler>
for generating and downloading MySqlBackup for the current users databases.

This class is based on the C<Cpanel::Server::Downloads::Base> base class
that is based C<Cpanel::Handler> base class.

It is designed to be used with the C<Cpanel::Server> object provided when
cpsrvd processes a cPanel route like: ./getsqlbackup/*

=head1 SYNOPSIS

  use Cpanel::Server::Downloads::MySqlBackup.pm ();
  my $handler = Cpanel::Server::Downloads::MySqlBackup->new(
      server_obj => $server_obj,
      document   => '/getsqlbackup/user1_db1.sql.gz',
      user       => $user,
      cpconf     => \%CPCONF,
  );
  $handler->serve();

=head1 CONSTRUCTOR

=head2 CLASS->new(ARGS)

Create a new instance of the handler to generate a MySQL backup archive.

=cut

sub new ( $class, %args ) {

    my $self = $class->SUPER::new(%args);

    my ($filename) = $self->document =~ m/^\.\/getsqlbackup\/+(.*)/;
    if ( !defined $filename || $filename eq '' ) {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a valid [asis,MySQL®] backup [asis,URL]. The [asis,URL] must include the filename to download and use the following format: [_2]', [ $self->document, '/getsqlbackup/<dbname>.sql.gz' ] );
    }
    $filename .= '.gz' if $filename !~ m/\.gz$/;
    $self->{filename} = $filename;

    my $db = $filename;
    $db =~ s/\.gz$//;
    $db =~ s/\.sql$//;

    $self->{db} = $db;

    return $self;
}

=head1 PROPERTIES

=head2 INSTANCE->filename()

string - the name of the requested file.

=cut

sub filename ($self) {
    return $self->{filename};
}

=head2 INSTANCE->db()

string - the name of the db you want to backup.

=cut

sub db ($self) {
    return $self->{db};
}

=head1 STATIC PROPERTIES

=head2 max_runtime

The maximum runtime to be set in Cpanel::Server::set_global_subprocess_timeout in cpsrvd.

=cut

sub max_runtime {
    return $Cpanel::Config::Constants::MySQL::TIMEOUT_MYSQLDUMP;
}

=head1 METHODS

=head2 INSTANCE->serve()

Generate a myql database backup and send it back to the caller in
a gzip archive.

=cut

sub serve ($self) {

    my $db = $self->db;
    if ( !defined $db || $db eq '' ) {
        return $self->internal_error( locale()->maketext('The system is unable to determine the database to back up from the supplied arguments.') );
    }

    return 1 if !$self->check_features(qw(backup));

    # Prechecks to run before we start streaming. Try to check for problems that
    # will prevent the backup from containing meaningful data.
    return 1 if !$self->_validate_db_ownership();

    $self->logaccess();
    $self->memorize_homedir();

    setpriority( 0, 0, 19 );
    my $connection = $self->server()->connection();
    if ( my $pid = Cpanel::FastSpawn::InOut::inout( my $mysql_in_fh, my $gz_out_fh, '/usr/local/cpanel/bin/gzip-wrapper', '--force', '-' ) ) {
        if ( my $mysqladminpid = fork() ) {
            close($mysql_in_fh);
            $self->_send_response( $gz_out_fh, $connection );
            waitpid( $mysqladminpid, 0 );
        }
        elsif ( defined $pid ) {
            require Cpanel::Encoder::URI;
            open( STDOUT, '>&=' . fileno($mysql_in_fh) );    ##no critic qw(InputOutput::ProhibitTwoArgOpen InputOutput::RequireCheckedOpen) -- only way to redirect STDOUT
            _exec( $self->cpconf()->{'root'} . '/bin/cpmysqlwrap', 'SQLBACKUP', Cpanel::Encoder::URI::uri_encode_str($db) ) or exit 1;
        }
        else {
            $self->internal_error("Failed to fork(): $!");
        }
    }
    else {
        $self->internal_error("Failed to fork(): $!");
    }

    return 0;
}

sub _exec (@args) {
    exec @args;
}

=head2 INSTANCE->_send_response(FH, CONNECTION) [PRIVATE]

Write out the response from the file handle to the socket.

=cut

sub _send_response ( $self, $gz_out_fh, $connection ) {

    my $filename = $self->filename;
    my $db       = $self->db;

    $self->send_targz_headers($filename);

    # Once we get here, any errors that occur will corrupt the
    # archived backup since they will be injected into the backup
    # itself. This is a limitation of the streaming nature of this
    # solution. We have already sent the success header above so
    # the user will never know the error has occurred until they
    # open the archive only to find an error instead of a backup.

    my $buffer;

    $self->server()->presend_object();
    while ( read( $gz_out_fh, $buffer, 65635 ) ) {
        $connection->write_buffer( \$buffer );
    }
    $self->server()->postsend_object();
    close($gz_out_fh);
    return;
}

=head2 INSTANCE->_validate_db_ownership() [PRIVATE]

Check if the current logged in user owns the requested dataabse and
reports failure as a HTTP 500 error.

=cut

sub _validate_db_ownership ($self) {
    my $db = $self->db;
    eval { Cpanel::AdminBin::Call::call( 'Cpanel', 'mysql', 'VERYIFY_DB_OWNER', $db ); };
    if ( my $exception = $@ ) {
        if ( $exception->isa('Cpanel::Exception::Database::DatabaseNotFound') ) {
            $self->send_404( locale()->maketext( 'Database not found: [_1]', $db ) );
        }
        else {
            $self->internal_error( locale()->maketext( 'The system failed to create the backup for the “[_1]” database.', $db ) );
        }
        return 0;
    }
    return 1;
}

1;
