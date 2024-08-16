package Cpanel::DBI::Postgresql;

# cpanel - Cpanel/DBI/Postgresql.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
#
# NOTE: This module does NOT accept "path" as a parameter.
#
# Use "host" to specify a socket directory. "hostaddr" works as well.
#
#----------------------------------------------------------------------

use strict;

use DBD::Pg ();

use parent qw( Cpanel::DBI::ConnectUsesHash Cpanel::DBI DBI );    # multi-level for perlcc

use Cpanel::Exception  ();
use Cpanel::LoadModule ();

our @preferred_driver_order = qw(
  Pg
);

my %unsupported_options = (
    Pg => ['debug'],
);

my $DBD_MODULE;

#For testing.
sub _reset_dbd_module {
    undef $DBD_MODULE;

    return;
}

sub _load_dbd_module {
    if ( !$DBD_MODULE ) {
        for my $module (@preferred_driver_order) {
            if ( $INC{"DBD/$module.pm"} ) {
                $DBD_MODULE = $module;
                last;
            }
        }

        if ( !$DBD_MODULE ) {
            my %failure;

            for my $module (@preferred_driver_order) {
                local $@;

                my $full_module = "DBD::$module";

                if ( eval { Cpanel::LoadModule::load_perl_module($full_module) } ) {
                    $DBD_MODULE = $module;
                    last;
                }
                else {
                    $failure{$full_module} = $@;
                }
            }

            if ( !$DBD_MODULE ) {
                die Cpanel::Exception::create( 'ModuleLoadError', 'The system could not load either of the following modules: [join,~, ,_1]', [ [ map { "$_ ($failure{$_})" } keys %failure ] ] );
            }
        }
    }

    return $DBD_MODULE;
}

sub _host_keys {
    my ($class) = @_;

    return ( $class->SUPER::_host_keys(), 'hostaddr' );
}

#NOTE: This module implements a pattern similar to Cpanel::DBI::Mysql for
#PostgreSQL. See that other module for more details.
sub _connect {
    my ( $class, $username, $password, $attrs_hr ) = @_;

    my %attrs = %$attrs_hr;

    my $driver = _load_dbd_module();

    my $unsupported_ar = $unsupported_options{$driver};
    if ( grep { defined $attrs{$_} } @$unsupported_ar ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The “[_1]” driver does not implement the following [numerate,_2,option,options]: [join,~, ,_3].', [ $driver, scalar(@$unsupported_ar), $unsupported_ar ] );
    }

    #"db", "dbname", and "database" are interchangeable.
    my %odbc = map { exists $attrs{$_} ? ( db => delete $attrs{$_} ) : () } qw(db dbname database);

    #NOTE: DBI drivers can be buggy when characters like \ are in the DB name.
    #DBD::Pg, for example, as of v3.0.0. To work around this, it’s safest just
    #to leave the database in the attributes hash.
    $attrs{'database'} = delete $odbc{'db'} if %odbc;

    #Workaround for https://rt.cpan.org/Ticket/Display.html?id=107763
    local $ENV{'PGDATABASE'} = $attrs{'database'};

    my @attrs_to_copy_to_odbc = ('port');

    if ( $driver eq 'Pg' ) {
        push @attrs_to_copy_to_odbc, qw(hostaddr host options sslmode);
    }
    else {

        #Take the first true value of these two keys, ensuring that we
        #delete them both regardless.
        # Note: host may be undef
        if ( my $host = ( grep length, map { delete $attrs{$_} } qw(hostaddr host) )[0] ) {

            #DBD::Pg combines 'host' and 'path' (they're mutually exclusive),
            my $odbc_host_key = ( $host =~ m{\A/} ) ? 'path' : 'host';
            $odbc{$odbc_host_key} = $host;
        }

        push @attrs_to_copy_to_odbc, 'debug';
    }

    for my $odbc_attr (@attrs_to_copy_to_odbc) {
        my $val = delete $attrs{$odbc_attr};
        if ( defined $val ) {
            $odbc{$odbc_attr} = $val;
        }
    }

    #Hopefully that 'path' will never include "=" or ";"...
    my $odbc_str = join( ';', map { "$_=$odbc{$_}" } keys %odbc );

    return $class->dbi_connect( "dbi:$driver:$odbc_str", $username, $password, \%attrs );
}

package Cpanel::DBI::Postgresql::db;

use parent qw( Cpanel::DBI::Exec Cpanel::DBI::Postgresql::Utils );    # for perlcc
use parent qw( -norequire Cpanel::DBI::db DBI::db);

use Cpanel::PostgresUtils::PgPass ();

my %attr_to_cmd_line_opt = qw(
  Username  username
  host      host
  port      port
);

sub _command_line_username_host_port {
    my ($self) = @_;

    my @opts;

    my $attr_hr = $self->attributes();
    while ( my ( $attr, $cmd_line ) = each %attr_to_cmd_line_opt ) {
        next if !length $attr_hr->{$attr};

        push @opts, "--$cmd_line=$attr_hr->{$attr}";
    }

    return @opts;
}

sub exec_with_credentials {
    my ( $self, %full_run_opts ) = @_;

    $full_run_opts{'args'} = [
        '--dbname' => $self->database(),
        $full_run_opts{'args'} ? @{ $full_run_opts{'args'} } : (),
    ];

    return $self->_exec(%full_run_opts);
}

sub _exec {
    my ( $self, %full_run_opts ) = @_;

    my $attr_hr = $self->attributes();

    my $pw_file_contents = join(
        ':',
        '*',
        '*',
        '*',
        '*',
        length( $attr_hr->{'Password'} ) ? $attr_hr->{'Password'} : q{},
    );

    my ( $temp_obj, $pwfile ) = $self->_write_temp_file($pw_file_contents);

    $full_run_opts{'args'} = [
        $self->_command_line_username_host_port(),
        $full_run_opts{'args'} ? @{ $full_run_opts{'args'} } : (),

        #PostgreSQL pre-8.4 doesn't have this option, but it should be added
        #once that's possible.
        #'--no-password',
    ];

    return $self->_exec_as_non_root(
        {
            %full_run_opts,
            before_exec => sub {
                $ENV{'PGPASSFILE'} = $pwfile;
                $full_run_opts{'before_exec'}->(@_) if $full_run_opts{'before_exec'};
            },
        }
    );
}

*_root_should_exec_as_this_user = \&Cpanel::PostgresUtils::PgPass::getpostgresuser;

*exec_with_credentials_no_db = \&_exec;

sub clone {
    my ( $self, $attrs_hr ) = @_;

    if ( !$attrs_hr || !%$attrs_hr ) {
        return $self->SUPER::clone( $attrs_hr || {} );
    }

    my $dbd_class = ref $self;
    $dbd_class =~ s{::db\z}{};

    my %new_attrs = %$attrs_hr;
    $dbd_class->normalize_attributes( \%new_attrs );

    my %connect_attrs = (
        %{ $self->attributes() },
        Username => $self->username(),
        Password => $self->password(),
        %new_attrs,
    );

    return $dbd_class->connect( \%connect_attrs );
}

package Cpanel::DBI::Postgresql::st;

use parent qw( -norequire Cpanel::DBI::st DBI::st );    # multi-level for perlcc

1;
