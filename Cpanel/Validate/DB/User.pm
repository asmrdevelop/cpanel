package Cpanel::Validate::DB::User;

# cpanel - Cpanel/Validate/DB/User.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Session::Constants  ();    # PPI USE OK - used in _init
use Cpanel::Validate::DB::Utils ();
use Cpanel::DB::Reserved        ();
use Cpanel::Exception           ();

our $max_mysql_dbuser_length;
our $max_pgsql_dbuser_length = 63;

my @reserved_dbuser_regexps;
my %reserved_usernames;

our $MARIADB_TEN_MIN_VERSION  = '10.0';
our $MODERN_MYSQL_MIN_VERSION = '5.7';

our $MODERN_MYSQL_DBUSER_LENGTH = 32;
our $LEGACY_DBUSER_LENGTH       = 16;

#MariaDB has a max length of 80.
#For future-proofing, we’ll plan for a world where we allow
#up to 32-byte usernames, though. The prefix underscore
#is one more character; so, the max we can allow is: 80 - 32 - 1 = 47.
our $POST_MARIADB_TEN_DBUSER_LENGTH = 47;

sub verify_mysql_dbuser_name {
    my ($dbuser) = @_;

    verify_mysql_dbuser_name_format($dbuser);

    _verify_dbuser_name_not_reserved($dbuser);

    return 1;
}

sub verify_pgsql_dbuser_name {
    my ($dbuser) = @_;

    verify_pgsql_dbuser_name_format($dbuser);

    _verify_dbuser_name_not_reserved($dbuser);

    return 1;
}

sub verify_pgsql_dbuser_name_format {
    my ($dbuser) = @_;

    _verify_dbuser_name_but_not_length($dbuser);

    my $err = Cpanel::Validate::DB::Utils::excess_statement( $dbuser, $max_pgsql_dbuser_length );
    if ($err) {
        die Cpanel::Exception::create_raw( 'InvalidParameter', "$err " . Cpanel::Validate::DB::Utils::locale()->maketext( 'A PostgreSQL username cannot exceed [quant,_1,character,characters].', $max_pgsql_dbuser_length ) );
    }

    return 1;
}

sub verify_mysql_dbuser_name_format {
    my ($dbuser) = @_;

    _verify_dbuser_name_but_not_length($dbuser);

    my ( $ok, $err ) = dbuser_name_length_check($dbuser);
    die Cpanel::Exception::create_raw( 'InvalidParameter', $err ) if !$ok;

    return 1;
}

sub reserved_username_check {
    _init();

    no warnings 'redefine';
    *reserved_username_check = \&_reserved_username_check;

    goto &_reserved_username_check;
}

sub get_max_mysql_dbuser_length {
    require Cpanel::Database;
    my $db = Cpanel::Database->new();
    return $db->max_dbuser_length;
}

sub _get_dbserver_name_and_version {
    require Cpanel::Mysql::Version;
    require Cpanel::MysqlUtils::Version;
    my $current_mysqlver = Cpanel::Mysql::Version::get_mysql_version();
    my $dbserver_name    = Cpanel::MysqlUtils::Version::is_at_least( $current_mysqlver, $MARIADB_TEN_MIN_VERSION ) ? "MariaDB" : "MySQL";
    return "$dbserver_name $current_mysqlver";
}

sub _reserved_username_check {
    my $user = shift;

    return 1 if exists $reserved_usernames{$user};

    for (@reserved_dbuser_regexps) {
        return 1 if $user =~ $_;
    }

    return 0;
}

sub _verify_dbuser_name_but_not_length {
    my ($dbuser) = @_;

    if ( !length $dbuser ) {
        die Cpanel::Exception::create( 'Empty', 'A username cannot be empty.' );
    }

    if ( $dbuser =~ tr/A-Za-z0-9_-//c ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The name of a database user on this system may include only the following characters: [join, ,_1]', [ [qw(A-Z a-z 0-9 - _)] ] );
    }

    return 1;
}

sub _verify_dbuser_name_not_reserved {
    my ($dbuser) = @_;

    if ( reserved_username_check($dbuser) ) {
        die Cpanel::Exception::create( 'Reserved', '“[_1]” is a reserved name for database users on this system.', [$dbuser], { value => $dbuser } );
    }

    return 1;
}

#This function verifies that a given username is short enough to be
#either a MySQL or a PostgreSQL username.
#
#NOTE: No need to check PostgreSQL here because, as of early 2014, MySQL
#usernames cannot be as long as PostgreSQL usernames, so anything that's
#short enough to be a valid MySQL username is also short enough to be a
#PostgreSQL username.
sub dbuser_name_length_check {
    my ($dbuser) = @_;

    my $err = Cpanel::Validate::DB::Utils::excess_statement( $dbuser, get_max_mysql_dbuser_length() );
    if ($err) {
        return (
            0,
            "$err " . Cpanel::Validate::DB::Utils::locale()->maketext(
                'A “[_1]” username cannot exceed [quant,_2,character,characters].',
                _get_dbserver_name_and_version(), get_max_mysql_dbuser_length()
            )
        );
    }

    return 1;
}

my $_called_init;

sub _init {
    return if $_called_init;

    @reserved_dbuser_regexps = (
        qr<\Acpmydns>i,
        qr<\A\Q$Cpanel::Session::Constants::TEMP_USER_PREFIX\E>i,
    );

    %reserved_usernames = map { $_ => 1 } Cpanel::DB::Reserved::get_reserved_usernames();

    $_called_init = 1;

    return;
}

1;
