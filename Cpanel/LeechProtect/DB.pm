package Cpanel::LeechProtect::DB;

# cpanel - Cpanel/LeechProtect/DB.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=head1 NAME

Cpanel::LeechProtect::DB - Interface to work with the LeechProtect SQLite DB.

=head1 SYNOPSIS

    use Cpanel::LeechProtect::DB;

    my $dbobj = Cpanel::LeechProtect::DB->new();
    $dbobj->get_hit_count( { 'ip' => '1.2.3.4', 'user' => 'htpasswd_user', 'dir' => '/path/to/secure_dir' } );

=cut

use Cpanel::Exception   ();
use Cpanel::LoadModule  ();
use Cpanel::DBI::SQLite ();

=head1 INTERFACE

=head2 BASE_DIR

Returns the base directory path for the leechprotect DB.
This is exposed as a function primarily for mocking purposes in unit tests.

=cut

sub BASE_DIR { return '/var/cpanel/leechprotect'; }

=head2 DB_FILE

Returns the full path for the leechprotect DB.
This is exposed as a function primarily for mocking purposes in unit tests.

=cut

sub DB_FILE { return BASE_DIR() . '/leechprotect.sqlite'; }

=head2 new

Object contructor.

=over 2

=item
Arguments

=over 3

=item
C<none>

=back

=item
Return

=over 3

=item
Reference to the object.

=back

=back

=cut

sub new {
    my $class = shift;

    my $self = bless { 'dbh' => undef }, $class;
    return $self->_initialize();
}

=head2 bump_hit_time_for_similar_ips

Object method.

Updates the hit time for entry from "similar" IPs. We consider
IPs within the same c-class to be similar for IPv4 addresses.

This method is a noop for IPv6 addresses.

=over 2

=item
Positional Arguments

=over 3

=item
C<Hashref> with the following data:

    'user' - The user logging into directory (note: this is the user configured in htpasswd)
    'dir'  - The directory "token" (the Digest::MD5::md5_hex( $protectdir . $token ) value)
    'ip'   - The IP address from which the user is logging in from

=back

=item
Return

=over 3

=item
A '1' indicating success.

Can throw an exception on error.

=back

=back

=cut

sub bump_hit_time_for_similar_ips {
    my ( $self, $entry_hr ) = @_;

    _validate_required_params($entry_hr);

    return 0 if $entry_hr->{'ip'} =~ tr/://;

    return $self->{'dbh'}->do(
        "UPDATE hits SET htime = strftime('%s', 'now') WHERE dir = ? AND user = ? AND ip LIKE ?;",
        {},
        $entry_hr->{'dir'},
        $entry_hr->{'user'},
        ( $entry_hr->{'ip'} =~ s/\.\d+$//r ) . '%',
    );
}

=head2 register_hit

Object method.

Creates or Updates the DB entry for a request.

=over 2

=item
Positional Arguments

=over 3

=item
C<Hashref> with the following data:

    'user' - The user logging into directory (note: this is the user configured in htpasswd)
    'dir'  - The directory "token" (the Digest::MD5::md5_hex( $protectdir . $token ) value)
    'ip'   - The IP dddress from which the user is logging in from

=back

=item
Return

=over 3

=item
A '1' indicating success.

Can throw an exception on error.

=back

=back

=cut

sub register_hit {
    my ( $self, $entry_hr ) = @_;

    _validate_required_params($entry_hr);

    return $self->{'dbh'}->do(
        "INSERT OR REPLACE INTO hits (dir, user, ip, htime) VALUES ( ?, ?, ?, strftime('%s', 'now') );",
        {},
        $entry_hr->{'dir'},
        $entry_hr->{'user'},
        $entry_hr->{'ip'},
    );
}

=head2 get_hit_count_from_other_ips

Object method.

Returns the number of hits registered for the user and directory from IP addresses B<NOT>
similar to the current request.

=over 2

=item
Positional Arguments

=over 3

=item
C<Hashref> with the following data:

    'user' - The user logging into directory (note: this is the user configured in htpasswd)
    'dir'  - The directory "token" (the Digest::MD5::md5_hex( $protectdir . $token ) value)
    'ip'   - The IP address from which the user is logging in from

=back

=item
Return

=over 3

=item
A '1' indicating success.

Can throw an exception on error.

=back

=back

=cut

sub get_hit_count_from_other_ips {
    my ( $self, $entry_hr ) = @_;

    _validate_required_params($entry_hr);

    my $count = $self->{'dbh'}->selectrow_array(
        "SELECT COUNT(ip) FROM hits WHERE dir = ? AND user = ? AND ip NOT LIKE ?;",
        undef,
        $entry_hr->{'dir'},
        $entry_hr->{'user'},
        ( $entry_hr->{'ip'} =~ s/\.\d+$//r ) . '%',
    );
    return $count ? $count : 0;
}

=head2 purge_old_records

Object method.

Removes registered hits that are older than 2 hours.

=over 2

=item
Positional Arguments

=over 3

=item
C<none>

=back

=item
Return

=over 3

=item
A '1' indicating success.

Can throw an exception on error.

=back

=back

=cut

sub purge_old_records {
    my $self = shift;

    # Remove any records with htime older than 2 hours
    $self->{'dbh'}->do("DELETE FROM hits WHERE htime < strftime('%s', 'now') - 7200;");

    return 1;
}

sub _initialize {
    my ($self) = @_;

    _setup_base_dir() if !-d BASE_DIR();
    if ( !-e DB_FILE() ) {
        open my $fh, '>', DB_FILE() or die "Unable to create DB: $!\n";    #touch
        close $fh;
        chmod 0600, DB_FILE() or die "Unable to set permissions on DB: $!\n";
    }

    # Cpanel::DBI::SQLite sets RaiseError.
    # It throws Cpanel::Exceptions on failure.
    $self->{'dbh'} = Cpanel::DBI::SQLite->connect( { 'db' => DB_FILE() } );

    # If the DB hasn't been initialized yet - i.e., this is the first
    # instance the SQlite DB is used - then initialize it as part of
    # the object creation.
    $self->initialize_db() if !-s DB_FILE();

    return $self;
}

=head2 initialize_db

Object method.

Initializes the LeechProtect DB, and creates the 'hits' table.
Automatically invoked upon Object creation if the DB does not exist or is not populated.

=over 2

=item
Positional Arguments

=over 3

=item
C<Scalar> - Force flag. If true, the existing 'hits' table will be dropped, and recreated.

=back

=item
Return

=over 3

=item
A '1' indicating success.

Can throw an exception on error.

=back

=back

=cut

sub initialize_db {
    my ( $self, $force ) = @_;

    $self->_create_hits_tbl($force);

    return 1;
}

sub _create_hits_tbl {
    my ( $self, $force ) = @_;

    $self->{'dbh'}->do('DROP TABLE IF EXISTS hits;') if $force;

    $self->{'dbh'}->do(
        <<END_OF_SQL
CREATE TABLE IF NOT EXISTS hits (
    dir CHAR(255) NOT NULL,
    user CHAR(128) NOT NULL,
    ip CHAR(255) NOT NULL,
    htime TIMESTAMP NOT NULL,
    PRIMARY KEY (dir, user, ip)
);
END_OF_SQL
    );

    return 1;
}

sub _setup_base_dir {
    Cpanel::LoadModule::load_perl_module('Cpanel::SafeDir::MK');
    Cpanel::SafeDir::MK::safemkdir( BASE_DIR(), 0700 )
      or die Cpanel::Exception::create( 'IO::DirectoryCreateError', [ 'path' => BASE_DIR(), 'error' => $! ] );

    return 1;
}

sub _validate_required_params {
    my $opts = shift;

    my @exceptions;
    foreach my $required_arg (qw(ip user dir)) {
        push @exceptions, Cpanel::Exception::create( 'MissingParameter', 'The parameter “[_1]” is required.', [$required_arg] ) if !defined $opts->{$required_arg};
    }

    die Cpanel::Exception::create( 'Collection', 'Invalid or Missing required parameters', [], { exceptions => \@exceptions } ) if scalar @exceptions;
    return 1;
}

1;
