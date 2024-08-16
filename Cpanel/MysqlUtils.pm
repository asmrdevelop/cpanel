package Cpanel::MysqlUtils;

# cpanel - Cpanel/MysqlUtils.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Try::Tiny;

use Cpanel::DbUtils                  ();
use Cpanel::MysqlUtils::Quote        ();
use Cpanel::MysqlUtils::Unquote      ();
use Cpanel::MysqlUtils::Connect      ();
use Cpanel::MysqlUtils::Command      ();
use Cpanel::MysqlUtils::Version      ();
use Cpanel::MysqlUtils::MyCnf::Basic ();

our $VERSION = '3.0';

=head1 NAME

Cpanel::MysqlUtils - miscellaneous MySQL-related functions

=head1 FUNCTIONS

=cut

my $mysql_bin;

{
    no warnings 'once';
    *find_mysql                      = *Cpanel::DbUtils::find_mysql;
    *find_mysql_config               = *Cpanel::DbUtils::find_mysql_config;
    *find_mysql_fix_privilege_tables = *Cpanel::DbUtils::find_mysql_fix_privilege_tables;
    *find_mysqldump                  = *Cpanel::DbUtils::find_mysqldump;
    *find_mysqladmin                 = *Cpanel::DbUtils::find_mysqladmin;
    *find_mysqlcheck                 = *Cpanel::DbUtils::find_mysqlcheck;
    *find_mysqld                     = *Cpanel::DbUtils::find_mysqld;
    *_getmydb_param                  = *Cpanel::MysqlUtils::MyCnf::Basic::_getmydb_param;
    *_getmydbparm                    = *Cpanel::MysqlUtils::MyCnf::Basic::_getmydbparm;
    *getmydbuser                     = *Cpanel::MysqlUtils::MyCnf::Basic::getmydbuser;
    *getmydbpass                     = *Cpanel::MysqlUtils::MyCnf::Basic::getmydbpass;
    *getmydbhost                     = *Cpanel::MysqlUtils::MyCnf::Basic::getmydbhost;
    *getmydbport                     = *Cpanel::MysqlUtils::MyCnf::Basic::getmydbport;
    *is_remote_mysql                 = *Cpanel::MysqlUtils::MyCnf::Basic::is_remote_mysql;
    *find_mysql_upgrade              = *Cpanel::DbUtils::find_mysql_upgrade;
    *quote                           = *Cpanel::MysqlUtils::Quote::quote;
    *quote_conf_value                = *Cpanel::MysqlUtils::Quote::quote_conf_value;
    *quote_pattern_identifier        = *Cpanel::MysqlUtils::Quote::quote_pattern_identifier;
    *quote_pattern                   = *Cpanel::MysqlUtils::Quote::quote_pattern;
    *escape_pattern                  = *Cpanel::MysqlUtils::Quote::escape_pattern;
    *unescape_pattern                = *Cpanel::MysqlUtils::Quote::unescape_pattern;
    *quote_identifier                = *Cpanel::MysqlUtils::Quote::quote_identifier;
    *safesqlstring                   = *Cpanel::MysqlUtils::Quote::safesqlstring;
    *unquote                         = *Cpanel::MysqlUtils::Unquote::unquote;
    *unquote_pattern                 = *Cpanel::MysqlUtils::Unquote::unquote_pattern;
    *unquote_identifier              = *Cpanel::MysqlUtils::Unquote::unquote_identifier;
    *unquote_pattern_identifier      = *Cpanel::MysqlUtils::Unquote::unquote_pattern_identifier;
    *mysqlversion                    = *Cpanel::MysqlUtils::Version::get_mysql_version_with_fallback_to_default;
    *sqlcmd                          = *Cpanel::MysqlUtils::Command::sqlcmd;
    *db_exists                       = *Cpanel::MysqlUtils::Command::db_exists;
    *user_exists                     = *Cpanel::MysqlUtils::Command::user_exists;

}

#This die()s if instantiation fails.
sub new {
    shift @_ if ( $_[0] eq __PACKAGE__ );    # Strip off this class name from the args list.

    my $obj = Cpanel::MysqlUtils::Connect->new(@_) or die "Could not connect using Cpanel::MysqlUtils::Connect: $@";
    return $obj->{'dbh'};
}

# stole from Cpanel::DB::Mysql::Connection::CMD

sub _set_binding {
    my ( $stmt, @bind ) = @_;

    # Count the number of question-marks in the statement
    # my $bind_count = ($stmt =~ tr/?//);

    # The number of question-marks and the number of elements in the array must match
    if ( ( scalar @bind > 0 ) and ( ( $stmt =~ tr/?// ) == scalar @bind ) ) {
        return join( '', map { $_, @bind ? quote( shift @bind ) : () } split( m/\?/, $stmt ) );
    }

    return $stmt;
}

sub fetch_hashref {
    return Cpanel::MysqlUtils::Connect->instance()->fetch_hashref(@_);
}

sub do_sql {
    my ( $stmt, @bind ) = @_;

    local $@;

    $stmt = _set_binding( $stmt, @bind );

    my $data = _runsqlcmd($stmt);

    return ( $@ || $data =~ m/^\s*ERROR/ ) ? 0 : 1;
}

sub _runsqlcmd {
    return sqlcmd( $_[0], { 'nodb' => 1, 'column_names' => 1 } );
}

sub build_mysql_exec_env {
    my ($env) = @_;

    $mysql_bin ||= find_mysql();
    return sub {

        my ($sql) = @_;

        if ( open( my $mysql_input_fh, '|-' ) ) {
            print {$mysql_input_fh} $sql;
            close($mysql_input_fh);
        }
        else {
            local $ENV{'MYSQL_PWD'} = $env->{'dbpass'};
            exec $mysql_bin, '--no-defaults', '-h', $env->{'dbhost'}, '-u', $env->{'dbuser'}, ( $env->{'dbport'} ? ( '--port', $env->{'dbport'} ) : () ), $env->{'db'};
            die "Could not exec($mysql_bin)";
        }
    }
}

1;
