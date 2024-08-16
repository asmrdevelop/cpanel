package Cpanel::MysqlUtils::ResetRootPassword;

# cpanel - Cpanel/MysqlUtils/ResetRootPassword.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Finally                      ();
use Cpanel::ConfigFiles                  ();
use Cpanel::PwCache                      ();
use Cpanel::ChildErrorStringifier        ();
use Cpanel::MysqlUtils::Quote            ();
use Cpanel::DbUtils                      ();
use Cpanel::MysqlUtils::Service          ();
use Cpanel::Rand                         ();
use Cpanel::AccessIds::ReducedPrivileges ();
use Cpanel::PasswdStrength::Check        ();
use Cpanel::PasswdStrength::Generate     ();
use Cpanel::Locale                       ();
use Cpanel::LoadModule                   ();
use Cpanel::MysqlUtils::Dir              ();

use constant _ENOENT => 2;

our $PASSWORD_LENGTH     = 16;
our $MAX_PASSWORD_LENGTH = 128;

my $default_minimum_password_length                 = 8;
my $default_minimum_number_of_mixed_case_characters = 1;
my $default_minimum_number_of_special_characters    = 1;
my $default_minimum_number_of_numeric_characters    = 1;

my $locale;

=encoding utf-8

=head1 NAME

Cpanel::MysqlUtils::ResetRootPassword - Forcefully (will restart mysql) reset the local mysql root password.

=head1 DESCRIPTION

This module will go though the "lost" password procedure in
order to reset the root mysql password.  If you already
have the mysql root password, please see Cpanel::MysqlUtils::RootPassword
as it is far safer.

=cut

# TODO: Combine logic in t/lib/Test/Password.pm into
# a Cpanel namespace module in 11.46 or later
sub get_root_password_that_meets_password_strength_requirements {
    my $password_length_to_generate = $PASSWORD_LENGTH;

    # Quotes are not allowed in MySQL password because MySQL
    # does not handle them well.
    #
    # Specificly, the mysql_upgrade utility causes a mess
    # on upgrade if there are quotes in the .my.cnf.
    #
    # Please see
    # http://bugs.mysql.com/bug.php?id=48392
    # and case 73533
    #
    my $dbpassword;
    while ( !$dbpassword || $dbpassword =~ m/['"]/ || !_does_mysql_root_password_meet_default_requirements($dbpassword) || Cpanel::PasswdStrength::Check::get_password_strength($dbpassword) < 100 ) {
        $dbpassword = Cpanel::PasswdStrength::Generate::generate_password( $password_length_to_generate, no_othersymbols => 1 );

        if ( ++$password_length_to_generate > $MAX_PASSWORD_LENGTH ) {

            # This will protect us from in infinite loop
            $locale ||= Cpanel::Locale->get_handle();
            die $locale->maketext("Failed to generate a valid password.");
        }
    }

    return $dbpassword;
}

sub _does_mysql_root_password_meet_default_requirements {
    my ($password) = @_;

    if ( length $password < $default_minimum_password_length ) {
        return 0;
    }
    elsif ( ( $password =~ tr/A-Z// ) < $default_minimum_number_of_mixed_case_characters ) {
        return 0;
    }
    elsif ( ( $password =~ tr/a-z// ) < $default_minimum_number_of_mixed_case_characters ) {
        return 0;
    }
    elsif ( ( $password =~ tr/0-9// ) < $default_minimum_number_of_numeric_characters ) {
        return 0;
    }
    elsif ( ( $password =~ tr/ "'A-Za-z0-9//c ) < $default_minimum_number_of_special_characters ) {    # " and ' aren't allowed due to mysql_upgrade issue - see above
        return 0;
    }

    return 1;
}

#### Object methods
###########################################################################
#
# Method:
#   new
#
# Description:
#   Create a MysqlUtils::ResetRootPassword object that can be used to reset
#   the mySQL root password without knowing the password.
#
# Parameters:
#   password - The password to set for the MySQL 'root' user
#
# Exceptions:
#   dies on invalid password
#
# Returns:
#   A Cpanel::MysqlUtils::ResetRootPassword object
#
sub new {
    my ( $class, %OPTS ) = @_;

    my $self = { 'password' => $OPTS{'password'}, 'mysql8_compat' => $OPTS{'mysql8_compat'} // _is_mysql8() };

    bless $self, $class;

    $self->_validate_mysql_root_pass_or_die();

    $self->{'start_time'} = time();

    return $self;
}

sub reset {
    my ($self) = @_;

    local $@;
    foreach my $func (qw(_create_password_change_init_file _reset_mysql_password_using_init_file)) {
        my ( $status, $statusmsg ) = $self->$func();
        return ( $status, $statusmsg ) if !$status;
    }

    # Resetting the password will shutdown MySQL because it needs to start
    # it up with a special init file.
    #
    # We need to get it back online for normal operation.
    #
    # This function doesn't return anything useful however

    # we could consider moving this logic to Cpanel::Services::Restart::restartservice itself
    #   but as now this is only place where we require this leave it like this
    my $use_script = 1;
    if ( my $get_service = 'scripts::restartsrv_base'->can('get_current_service') ) {
        my $service = $get_service->();
        if ( $service->isa('Cpanel::ServiceManager::Services::Mysql') ) {
            $use_script = 0;
            $service->restart();
        }
    }

    # fallback to full /scripts/restarsrv_mysql call
    require Cpanel::Services::Restart;
    Cpanel::Services::Restart::restartservice('mysql') if $use_script;

    $locale ||= Cpanel::Locale->get_handle();
    return ( 1, $locale->maketext("The [asis,MySQL] root password was reset.") );
}

sub _create_password_change_init_file {
    my ($self) = @_;

    require Cpanel::Database;
    my $db_obj = Cpanel::Database->new();

    my $mysqldir = Cpanel::MysqlUtils::Dir::getmysqldir() || Cpanel::PwCache::gethomedir('mysql');

    my $quoted_password = Cpanel::MysqlUtils::Quote::quote( $self->{'password'} );

    my $root_pw_init_sql = $db_obj->get_root_pw_init_file_sql($quoted_password);

    return Cpanel::AccessIds::ReducedPrivileges::call_as_user(
        sub {
            # This file is named oddly to ensure MySQL ignores it in the event something goes wrong and it is not removed.
            # audit case 46806 ok
            # See http://bugs.mysql.com/bug.php?id=53797
            my ( $initfile, $fh ) = Cpanel::Rand::get_tmp_file_by_name("$mysqldir/.-");

            if ( -d $mysqldir && $initfile && $initfile ne '/dev/null' ) {
                print {$fh} join( "\n", @$root_pw_init_sql ) . "\n";
                close($fh);
                $self->{'init_file'} = $initfile;
                return ( 1, $locale->maketext('The [asis,MySQL] init-file was created successfully.') );
            }
            else {
                return ( 0, $locale->maketext('The [asis,MySQL] init-file could not be created.') );
            }
        },
        'mysql'
    );

}

sub _wait_for_mysql_to_run_init_file {
    my ($self) = @_;

    return Cpanel::MysqlUtils::Service::wait_for_mysql_to_startup( $self->{'start_time'} );
}

sub _reset_mysql_password_using_init_file {
    my ($self) = @_;

    $locale ||= Cpanel::Locale->get_handle();
    return ( 0, $locale->maketext( "The “[_1]” property is required.", 'init_file' ) ) if !$self->{'init_file'};
    my $finally = Cpanel::Finally->new(
        sub {
            unlink( $self->{'init_file'} ) or do {
                warn "unlink($self->{'init_file'}): $!" if $! != _ENOENT;
            };
        },
    );

    Cpanel::MysqlUtils::Service::safe_shutdown_local_mysql();

    sleep(1) while $self->{'start_time'} == time();    # if its too fast it will fail

    Cpanel::LoadModule::load_perl_module('Cpanel::Daemonizer::Tiny');
    my $mysqlchildpid = Cpanel::Daemonizer::Tiny::run_as_daemon(
        sub {
            local $ENV{'USER'} = 'root';
            local $ENV{'HOME'} = '/root';

            open( STDERR, '>>', $Cpanel::ConfigFiles::CPANEL_ROOT . '/logs/error_log' ) or warn "Could not open cPanel Error Log: $!";
            open( STDOUT, '>>', $Cpanel::ConfigFiles::CPANEL_ROOT . '/logs/error_log' ) or warn "Could not open cPanel Error Log: $!";

            # A pid file must be created to ensure that _wait_for_mysql_to_run_init_file() can find this process.
            exec( scalar Cpanel::DbUtils::find_mysqld(), '-u', 'mysql', '--pid-file', scalar Cpanel::MysqlUtils::Service::get_mysql_pid_file(), '--init-file', $self->{'init_file'} ) or exit($!);
        }
    );

    my ( $ran_ok, $run_msg ) = $self->_wait_for_mysql_to_run_init_file();

    Cpanel::MysqlUtils::Service::safe_shutdown_local_mysql();

    if ( waitpid( $mysqlchildpid, 0 ) > 0 ) {
        my $child_err = Cpanel::ChildErrorStringifier->new($?);
        if ( $child_err->CHILD_ERROR() ) {
            return ( 0, $child_err->autopsy() );
        }
    }

    return ( $ran_ok, $run_msg );
}

sub _validate_mysql_root_pass_or_die {
    my ($self) = @_;

    $locale ||= Cpanel::Locale->get_handle();
    if ( !length $self->{'password'} ) {
        die $locale->maketext( "The “[_1]” argument is required.", 'password' );
    }

    if ( !Cpanel::PasswdStrength::Check::check_password_strength( 'pw' => $self->{'password'}, 'app' => 'mysql' ) ) {
        my $required_strength = Cpanel::PasswdStrength::Check::get_required_strength('mysql');
        $locale ||= Cpanel::Locale->get_handle();
        die $locale->maketext("The password you selected cannot be used because it is too weak and would be too easy to guess.") . ' ' . $locale->maketext( "Please select a password with strength rating of [numf,_1] or higher.", $required_strength );
    }

    return 1;
}

sub _is_mysql8 {

    # This must return the local service version when a remote profile is active.
    require Cpanel::MysqlUtils::Version;
    my $version = Cpanel::MysqlUtils::Version::get_local_mysql_version_with_fallback_to_default();
    return Cpanel::MysqlUtils::Version::is_at_least( $version, '8.0' ) ? 1 : 0;
}

1;
