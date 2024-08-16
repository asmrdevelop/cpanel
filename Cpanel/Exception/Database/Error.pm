package Cpanel::Exception::Database::Error;

# cpanel - Cpanel/Exception/Database/Error.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# NOTE: This exception class is best suited for errors that originate
# from the database rather than from the application.
#----------------------------------------------------------------------

use strict;
use warnings;

use parent qw( Cpanel::Exception );

use Cpanel::LoadModule   ();
use Cpanel::LocaleString ();

my %ERRCODE_MODULE = qw(
  mysql   Cpanel::Mysql::Error
  Pg      Cpanel::Postgres::Error
  SQLite  Cpanel::DBI::SQLite::Error
);

my %ERRCODE_IS_AT = qw(
  mysql   error_code
  Pg      state
  SQLite  error_code
);

#taken from the return of $dbh->get_info(SQL_DBMS_NAME) for each driver
my %SQL_DBMS_NAME = qw(
  mysql   MySQL
  Pg      PostgreSQL
  SQLite  SQLite
);

#This abstracts away where the DBI driver reports the error code
#from the DB client library and returns a boolean that says whether
#the error that this object represents matches the given error.
#
#The name "failure" is deliberate and meant to avoid similitude/confusion
#with how DBI names the error/state information.
#
sub failure_is {
    my ( $self, $name ) = @_;

    my $driver = $self->get("dbi_driver");

    my $module = $ERRCODE_MODULE{$driver};
    die "Wrong driver? ($driver)" if !length $module;

    Cpanel::LoadModule::load_perl_module($module);

    my $cr = $module->can($name) or die "Invalid: $module\::$name";

    my $this_code = $self->_err_code();
    die "No code??" if !length $this_code;

    return $cr->() eq $this_code ? 1 : 0;
}

sub _err_code {
    my ($self) = @_;

    my $driver = $self->get("dbi_driver");
    my $code   = $self->get( $ERRCODE_IS_AT{$driver} );

    return $code;
}

sub _err_code_for_display {
    my ($self) = @_;

    my $err_name;

    my $err_code = $self->_err_code();

    my $driver = $self->get("dbi_driver");

    if ($err_code) {
        my $module = $ERRCODE_MODULE{$driver};
        Cpanel::LoadModule::load_perl_module($module);
        my $get_name_cr = $module->can('get_name_for_error') or die "$module has no get_name_for_error()!";
        $err_name = $get_name_cr->($err_code);
    }

    return $err_name || $err_code;
}

sub _err_message_for_display {
    my ($self) = @_;

    return $self->get('error_string') || $self->get('message') || 'Unknown';
}

#overridden in subclass
sub _locale_string_with_dbname {
    return Cpanel::LocaleString->new('The system received an error from the “[_1]” database “[_2]”: [_3]');
}

#overridden in subclass
sub _locale_string_without_dbname {
    return Cpanel::LocaleString->new('The system received an error from “[_1]”: [_2]');
}

#Metadata parameters:
#   message - required
#   database - optional, name of the database
#
sub _default_phrase {
    my ($self) = @_;

    my $err_msg = $self->_err_message_for_display();

    my $err_name = $self->_err_code_for_display();

    #Parens should be language-neutral … right?
    $err_msg = "$err_name ($err_msg)" if $err_name;

    my $dbname = $self->get('database');

    my $dbms_name = $SQL_DBMS_NAME{ $self->get('dbi_driver') };

    if ($dbname) {
        return $self->_locale_string_with_dbname()->clone_with_args( $dbms_name, $dbname, $err_msg );
    }

    return $self->_locale_string_without_dbname()->clone_with_args( $dbms_name, $err_msg );
}

1;
