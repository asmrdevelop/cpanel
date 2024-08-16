
# cpanel - Cpanel/ModSecurity/DB.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::ModSecurity::DB;

use strict;

use Cpanel::Exception        ();
use Cpanel::LoadModule       ();
use Cpanel::DBI::SQLite      ();
use Cpanel::Validate::IP     ();
use Cpanel::Validate::IP::v4 ();

# No locale here since this gets included in tailwatchd

=head1 NAME

Cpanel::ModSecurity::DB

=head1 DESCRIPTION

A module for handling ModSecurity Database related tasks.

=cut

# Each of these validators, when given a value, should do one of three things:
#
#   1. Return the value exactly as it was provided because it meets the validation criteria.
#   2. Return a modified version of the value (e.g., truncated) in order to fit the criteria.
#   3. Die with a message describing the reason the validation completely failed.

# Important: The order of these fields matters and will dictate the order of columns
# used by callers of columns().

my %validators = (    #
    'timestamp'     => sub { validate_datetime(shift) },          #
    'ip'            => sub { validate_ip(shift) },                #
    'http_version'  => sub { truncate_varchar( shift, 8 ) },      #
    'http_method'   => sub { truncate_varchar( shift, 7 ) },      #
    'http_status'   => sub { validate_status(shift) },            #
    'host'          => sub { truncate_varchar( shift, 254 ) },    #
    'path'          => sub { validate_text(shift) },              #
    'handler'       => sub { truncate_varchar( shift, 254 ) },    #
    'justification' => sub { validate_text(shift) },              #
    'action_desc'   => sub { validate_text(shift) },              #
    'meta_file'     => sub { truncate_varchar( shift, 254 ) },    #
    'meta_line'     => sub { truncate_varchar( shift, 20 ) },     #
    'meta_offset'   => sub { validate_numeric( shift || 0 ) },    #
    'meta_rev'      => sub { truncate_varchar( shift, 20 ) },     #
    'meta_msg'      => sub { validate_text(shift) },              #
    'meta_id'       => sub { validate_numeric( shift || 0 ) },    #
    'meta_logdata'  => sub { validate_text(shift) },              #
    'meta_uri'      => sub { validate_text(shift) },              #
    'meta_severity' => sub { truncate_varchar( shift, 9 ) },      #
    'timezone'      => sub { validate_timezone(shift) },          #
);                                                                #

my @ordered_validators = (                                        #
    'timestamp',
    'ip',
    'http_version',
    'http_method',
    'http_status',
    'host',
    'path',
    'handler',
    'justification',
    'action_desc',
    'meta_file',
    'meta_line',
    'meta_offset',
    'meta_rev',
    'meta_msg',
    'meta_id',
    'meta_logdata',
    'meta_uri',
    'meta_severity',
    'timezone'
);    #

=head1 SUBROUTINES

=cut

=head2 BASE_DIR

Returns the base directory path for the modsec DB.
This is exposed as a function primarily for mocking purposes in unit tests.

=cut

sub BASE_DIR { return '/var/cpanel/modsec'; }

=head2 DB_FILE

Returns the full path for the modsec DB.
This is exposed as a function primarily for mocking purposes in unit tests.

=cut

sub DB_FILE { return BASE_DIR() . '/modsec.sqlite'; }

sub validate {
    my ( $validation_type, $value ) = @_;
    my $validator = $validators{$validation_type};
    if ( ref $validator eq 'CODE' ) {
        my $result = eval { $validator->($value) };
        if ( chomp( my $error = $@ ) ) {
            die "The value “$value” of type “$validation_type” was invalid: $error\n";    # No locale because this gets included in tailwatchd
        }
        return $result;
    }
    die qq{No validator was found for type “[$validation_type]”.\n};                      # should be unreachable except in case of a bug
}

sub validate_datetime {
    my $timestamp = shift;
    if ( $timestamp =~ m{^([0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2})$} ) {
        return $1;
    }
    die qq{Invalid timestamp: $timestamp\n};
}

sub validate_timezone {
    my $offset = shift;
    if ( $offset =~ m{^-?[0-9]+$} ) {
        return $offset if abs($offset) <= 840;
    }
    die qq{Invalid timezone offset: $offset\n};
}

sub validate_varchar {
    my ( $string, $width ) = @_;
    return undef if !defined $string;
    my $len = length $string;
    if ( $len <= $width ) {
        return $string;
    }
    die "The string is $len, which exceeds the $width varchar width.\n";    # No locale because this gets included in tailwatchd
}

sub truncate_varchar {
    my ( $string, $width ) = @_;
    return undef if !defined $string;
    if ( length($string) <= $width ) {
        return $string;
    }
    return substr $string, 0, $width;
}

sub validate_status {
    my $status = shift;
    return unless defined $status;    # NULL inserted for status is valid when a status is not reported
    if ( validate_numeric($status) ) {
        return $status if $status >= 100 && $status < 600;
    }
    die qq{Invalid HTTP status: $status\n};    # No locale because this gets included in tailwatchd
}

sub validate_numeric {
    my $number = shift;
    if ( $number =~ m{^(-?[0-9]+)$} ) {
        return $1;
    }
    die qq{Invalid number: $number\n};         # No locale because this gets included in tailwatchd
}

sub validate_text {
    return shift;
}

sub validate_ip {
    my $ip = shift;
    return $ip if Cpanel::Validate::IP::v4::is_valid_ipv4($ip) || Cpanel::Validate::IP::is_valid_ipv6($ip);
    die qq{Invalid IP address: $ip\n};         # No locale because this gets included in tailwatchd
}

=head2 initialize_database()

Creates the SQLite DB for the ModSecurity sub-system.

=head3 Arguments

    - force - Boolean - If evaluates to truthy value, the routine will drop the hits table if it
                        exists. Otherwise, the table will only get created if it doesn't already exist.

=head3 Returns

n/a

=head3 Throws

If an error occurs, this function will throw exceptions.
Callers must either catch exceptions or be willing to end on the first failure.

=cut

sub initialize_database {
    my $force = shift;

    create_database();
    create_schema($force);

    return 1;
}

=head2 create_schema()

Creates the tables for the ModSecurity sub-system.


=head3 Arguments

none

=head3 Returns

n/a

=head3 Throws

If an error occurs, this function will throw exceptions.
Callers must either catch exceptions or be willing to end on the first failure.

=cut

sub create_schema {
    my $force = shift;

    my $dbh = get_dbh();

    if ($force) {
        $dbh->do('DROP TABLE IF EXISTS `hits`;');
    }

    $dbh->do(
        'CREATE TABLE IF NOT EXISTS `hits` (
          `id` INTEGER PRIMARY KEY NOT NULL,
          `timestamp` datetime DEFAULT NULL,
          `timezone` int DEFAULT 0,
          `ip` varchar(39) DEFAULT NULL,
          `http_version` varchar(8) DEFAULT NULL,
          `http_method` varchar(7) DEFAULT NULL,
          `http_status` int DEFAULT NULL,
          `host` varchar(254) DEFAULT NULL,
          `path` text DEFAULT NULL,
          `handler` varchar(254) DEFAULT NULL,
          `justification` text DEFAULT NULL,
          `action_desc` text DEFAULT NULL,
          `meta_file` varchar(254) DEFAULT NULL,
          `meta_line` varchar(20) DEFAULT NULL,
          `meta_offset` int DEFAULT NULL,
          `meta_rev` varchar(20) DEFAULT NULL,
          `meta_msg` text,
          `meta_id` bigint DEFAULT 0,
          `meta_logdata` text,
          `meta_severity` varchar(9) DEFAULT NULL,
          `meta_uri` text
        );'
    ) or die $dbh->errtr();

    return 1;
}

=head2 create_database()

Creates the database for the ModSecurity sub-system.

=head3 Arguments

none

=head3 Returns

n/a

=head3 Throws

If an error occurs, this function will throw exceptions.
Callers must either catch exceptions or be willing to end on the first failure.

=cut

sub create_database {
    _setup_base_dir() if !-d BASE_DIR();

    if ( !-e DB_FILE() ) {
        open my $fh, '>', DB_FILE() or die "Unable to create DB: $!\n";    #touch
        close $fh;
        chmod 0600, DB_FILE() or die "Unable to set permissions on DB: $!\n";
    }

    return 1;
}

sub columns {
    return 'id', @ordered_validators;
}

=head2 purge_stale_records_from_database()

Removes old records from the modsec "hits" table, based on the a specified number of days.

=head3 Arguments

    - days     - Numeric - Optional, if provided will determine the number of days to keep; if zero, no delete will
                                     be performed. Default value is 7 days.

=head3 Returns

n/a

=cut

sub purge_stale_records_from_database {
    my $days = shift // 7;
    return 1 if !$days;    # Don't purge anything.

    return get_dbh()->do(
        "DELETE FROM `hits` WHERE `timestamp` < datetime('now', ?);",
        undef,
        '-' . $days . ' days'
    );
}

#---------------------------------------
# Private methods
#---------------------------------------
sub _hits_table_exists {
    my ($dbh) = @_;
    my $query = q{SELECT COUNT(*) FROM `information_schema`.`TABLES` WHERE `TABLE_SCHEMA` = 'modsec' AND `TABLE_NAME` = 'hits'};
    my $rows  = $dbh->selectall_arrayref($query);
    return $rows->[0][0];
}

sub get_dbh {

    # create_database() will be a noop if the BASE_DIR and DB_FILE already exist.
    # We need to do this to account for cases where get_dbh() is called directly without
    # first calling initialize_database() to ensure that the permissions
    # are set properly.
    create_database();

    return Cpanel::DBI::SQLite->connect( { 'db' => DB_FILE() } );
}

sub _setup_base_dir {
    Cpanel::LoadModule::load_perl_module('Cpanel::SafeDir::MK');
    Cpanel::SafeDir::MK::safemkdir( BASE_DIR(), 0700 )
      or die Cpanel::Exception::create( 'IO::DirectoryCreateError', [ 'path' => BASE_DIR(), 'error' => $! ] );

    return 1;
}

1;
