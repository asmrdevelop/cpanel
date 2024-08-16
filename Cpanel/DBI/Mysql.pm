package Cpanel::DBI::Mysql;

# cpanel - Cpanel/DBI/Mysql.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use parent qw( Cpanel::DBI::ConnectUsesHash Cpanel::DBI DBI );

use Cpanel::Compat::DBDmysql ();
use Cpanel::DbUtils          ();

my $DSN_DRIVER_NAME = 'mysql';

#NOTE: This method's signature differs from that of plain DBI::connect() in an
#effort to simplify the relationship between connect() and clone(). We do so
#by completely ignoring the "ODBC" component of the DSN and instead passing in
#everything as an attribute. This *sort* of relies on DBD::mysql::connect()'s
#parse of the ODBC args into the arguments hash, which is bending the rules
#a bit, but the payoff seems worthwhile.
#
#Give a hashref of name/value pairs that would go in the "attributes" hashref.
#Put un/pw as 'Username' and 'Password'. (Documented in DBI, but broken
#in DBD::mysql.)
#
#So, instead of:
#   my $dbh = DBI->connect('DBI:mysql:host=foo.tld', 'johndoe', 'p4$$w0rd')
#...do:
#   my $dbh = Cpanel::DBI::Mysql->connect( {
#       host => 'foo.tld',
#       Username => 'johndoe',
#       Password => 'p4$$w0rd',
#   } )
sub _connect {
    my ( $class, $username, $password, $attrs_hr ) = @_;

    return $class->dbi_connect(
        'dbi:mysql:',
        $username,
        $password,
        {
            mysql_local_infile => 0,
            %$attrs_hr,
        },
    );
}

package Cpanel::DBI::Mysql::db;

use parent qw( Cpanel::DBI::Exec Cpanel::DBI::Mysql::Utils );
use parent qw( -norequire Cpanel::DBI::db DBI::db);

my %attr_to_defaults_file_opt = qw(
  Username        user
  host            host
  mysql_socket    socket
  port            port
);

#Returns key-value pairs to put into a "defaults file" to use for running
#command-line tools (e.g., mysqldump, mysqladmin) to connect to the same
#server, using the same credentials, as the current connection.
#NOTE: This does NOT include the actual MySQL database (i.e., what is "USE"d).
sub _defaults_file_options {
    my ($self) = @_;

    my @opts;

    my $attr_hr = $self->attributes();
    while ( my ( $attr, $defaults_file_opt ) = each %attr_to_defaults_file_opt ) {
        next if !length $attr_hr->{$attr};

        push @opts, ( $defaults_file_opt, $attr_hr->{$attr} );
    }

    push @opts, 'password', ( length $self->password() ? $self->password() : q{} );

    return @opts;
}

sub exec_with_credentials {
    my ( $self, %full_run_opts ) = @_;

    my %pw_file_opts = (
        $self->_defaults_file_options(),
        ( length( $self->database() ) ? ( database => $self->database() ) : () ),
    );

    return $self->_exec( \%pw_file_opts, \%full_run_opts );
}

sub exec_with_credentials_no_db {
    my ( $self, %full_run_opts ) = @_;

    my %pw_file_opts = (
        $self->_defaults_file_options(),
    );

    return $self->_exec( \%pw_file_opts, \%full_run_opts );
}

sub _exec_program_path_hr {
    return {
        mysql     => \&Cpanel::DbUtils::find_mysql,
        mysqldump => \&Cpanel::DbUtils::find_mysqldump,
    };
}

sub write_temp_defaults_file {
    my ( $self, $defaults_file_opts_hr ) = @_;

    if ( !$defaults_file_opts_hr ) {
        $defaults_file_opts_hr = {
            $self->_defaults_file_options(),
        };
    }

    my $defaults_file_contents = "[client]$/";
    while ( my ( $key, $val ) = each %$defaults_file_opts_hr ) {
        $val =~ s{(["\\])}{\\$1}g;
        $defaults_file_contents .= qq{$key="$val"$/};
    }

    return $self->_write_temp_file($defaults_file_contents);
}

sub _exec {
    my ( $self, $pw_file_opts_hr, $full_run_opts_hr ) = @_;

    my ( $temp_obj, $pwfile ) = $self->write_temp_defaults_file($pw_file_opts_hr);

    $full_run_opts_hr->{'args'} = [
        "--defaults-file=$pwfile",
        $full_run_opts_hr->{'args'} ? @{ $full_run_opts_hr->{'args'} } : (),
    ];

    return $self->_exec_as_non_root($full_run_opts_hr);
}

sub _root_should_exec_as_this_user {
    return 'mysql';
}

sub clone {
    my ( $self, $attrs_hr ) = @_;

    if ( !$attrs_hr || !%$attrs_hr ) {
        return $self->SUPER::clone( $attrs_hr || () );
    }

    my $dbd_class = ref $self;
    $dbd_class =~ s{::db\z}{};

    my %normalized_attrs = %$attrs_hr;
    $dbd_class->normalize_attributes( \%normalized_attrs );

    return $dbd_class->connect( { %{ $self->attributes() }, %normalized_attrs } );
}

sub server_is_mariadb {
    my ($self) = @_;

    return $self->{'mysql_serverversion'} > 100000;
}

package Cpanel::DBI::Mysql::st;

use parent qw( -norequire Cpanel::DBI::st DBI::st );    # multi-level for perlcc

1;
