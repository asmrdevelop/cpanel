package Cpanel::MysqlUtils::Check;

# cpanel - Cpanel/MysqlUtils/Check.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::LoadModule          ();
use Cpanel::Mysql::Error        ();
use Cpanel::MysqlUtils::Connect ();
use Cpanel::Exception::Utils    ();

use Try::Tiny;

=encoding utf-8

=head1 NAME

Cpanel::MysqlUtils::Check - Check and reset the MySQL root password as needed

=head1 SYNOPSIS

    use Cpanel::MysqlUtils::Check;

    if (Cpanel::MysqlUtils::Check::check_mysql_password_works_or_reset()) {
        # password reset OK
    } else {
        # check error log for failure reason
    }

=cut

our $MYSQL_CONNECTION_CHECK_PATH = '/usr/local/cpanel/scripts/mysqlconnectioncheck';

=head2 check_mysql_password_works_or_reset()

Returns 1 if the MySQL root password is working or was successfully reset.

Returns 0 if the MySQL root password is not working and failed to reset.

=cut

sub check_mysql_password_works_or_reset {
    Cpanel::LoadModule::load_perl_module('Cpanel::SafeRun::Object');

    # Try to restore our connection to mysql if the password is wrong
    my $run = Cpanel::SafeRun::Object->new( 'program' => $MYSQL_CONNECTION_CHECK_PATH );
    if ( $run->CHILD_ERROR() ) {
        Cpanel::LoadModule::load_perl_module('Cpanel::Debug');
        Cpanel::Debug::log_warn( "$MYSQL_CONNECTION_CHECK_PATH failed: " . $run->autopsy() . ": " . $run->stderr() );
        return 0;
    }
    elsif ( my $output = $run->stdout() ) {
        Cpanel::LoadModule::load_perl_module('Cpanel::Debug');
        Cpanel::Debug::log_warn("$MYSQL_CONNECTION_CHECK_PATH: $output");

    }

    return 1;
}

sub check_mysql_connection {
    my $connection_ok              = 0;
    my $connection_failure_reason  = 'unknown';
    my $connection_failure_message = 'unknown';

    my $err;

    try {
        my $dbh = Cpanel::MysqlUtils::Connect::get_dbi_handle();
    }
    catch {
        $err = $_;
    };

    if ( !$err ) {
        $connection_ok = 1;
    }
    else {
        $connection_failure_message = Cpanel::Exception::Utils::traceback_to_error($err);

        my $err_code = $err->get('error_code');

        if ( grep { $_ eq $err_code } ( Cpanel::Mysql::Error::CR_CONNECTION_ERROR(), Cpanel::Mysql::Error::CR_CONN_HOST_ERROR() ) ) {
            $connection_failure_reason = 'cannot_connect';
        }
        elsif ( !Cpanel::Mysql::Error::is_client_error_code($err_code) ) {
            $connection_failure_reason = 'access_denied';
        }
    }

    return ( $connection_ok, $connection_failure_reason, $connection_failure_message );
}
1;
