package Cpanel::Services::Available;

# cpanel - Cpanel/Services/Available.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Services::Available

=head1 SYNOPSIS

    # no disabled-service awareness:
    my ($yn, $why) = Cpanel::Services::Available::ensure_sql_servers_are_available();

    # disabled-service-aware, exception-throwing:
    Cpanel::Services::Available::ensure_mysql_if_provided();
    Cpanel::Services::Available::ensure_postgresql_if_provided();

=cut

#----------------------------------------------------------------------

use Cpanel::Context              ();
use Cpanel::Exception            ();
use Cpanel::PostgresAdmin::Check ();
use Cpanel::Services::Enabled    ();

use Try::Tiny;

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 ensure_mysql_if_provided()

This throws an exception unless one of the following is true:

=over

=item * A - The MySQL service is disabled.

=item * B - The configured MySQL server (local or remote) can be connected to.

=back

=cut

sub ensure_mysql_if_provided {
    my $err;

    # NB: We can’t use Cpanel::Services::Enabled::is_provided() because
    # “provided” for that module means either remote configuration
    # or that the local *service* is enabled. To use that here would be to
    # consider all service-disabled states to be successes, but we want
    # to consider role-enabled-but-service-disabled a failure state here.

    my $mysql_expected_yn = Cpanel::Services::Enabled::is_provided('mysql');

    if ($mysql_expected_yn) {
        require Cpanel::MysqlUtils::Connect;

        try {
            Cpanel::MysqlUtils::Connect::get_dbi_handle();
        }
        catch {
            die _unavailable_err( 'MySQL/MariaDB', $_ );
        }
    }

    return;
}

#----------------------------------------------------------------------

=head2 ensure_postgresql_if_provided()

Like C<ensure_mysql_if_provided()>, but for PostgreSQL. (NB: Remote
PostgreSQL is currently not supported.)

=cut

sub ensure_postgresql_if_provided {
    if ( Cpanel::Services::Enabled::is_provided('postgresql') ) {
        require Cpanel::Postgres::Connect;

        try {
            Cpanel::Postgres::Connect::get_dbi_handle();
        }
        catch {
            die _unavailable_err( 'PostgreSQL', $_ );
        };
    }

    return;
}

sub _unavailable_err {
    my ( $engine, $err_obj ) = @_;

    return Cpanel::Exception->create( 'The “[_1]” server is currently unavailable because of an error: [_2]', [ $engine, Cpanel::Exception::get_string_no_id($err_obj) ] );
}

#----------------------------------------------------------------------

=head2 ( $ok, $err ) = ensure_sql_servers_are_available()

This ensures that MySQL/MariaDB can be connected to. It does the same with
PostgreSQL if installed.

Note that this does B<not> take roles into account. For example, this
function will ALWAYS throw an exception if the server’s MySQL role is
disabled.

Note also that, unlike the role-aware functions, this never throws an
exception.

=cut

sub ensure_sql_servers_are_available {
    my $err;

    Cpanel::Context::must_be_list();

    require Cpanel::MysqlUtils::Connect;
    try {
        Cpanel::MysqlUtils::Connect::get_dbi_handle();
    }
    catch {
        $err = $_;
    };
    if ($err) {
        return ( 0, _unavailable_err( 'MySQL/MariaDB', $err )->to_locale_string_no_id() );
    }

    if ( Cpanel::PostgresAdmin::Check::is_enabled_and_configured() ) {
        require Cpanel::Postgres::Connect;
        try {
            Cpanel::Postgres::Connect::get_dbi_handle();
        }
        catch {
            $err = $_;
        };
        if ($err) {
            return ( 0, _unavailable_err( 'PostgreSQL', $err )->to_locale_string_no_id() );
        }
    }

    return ( 1, 'available' );
}

1;
