package Whostmgr::API::1::LocalMySQL;

# cpanel - Whostmgr/API/1/LocalMySQL.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Try::Tiny;

use Cpanel::Exception                               ();
use Cpanel::Locale                                  ();
use Cpanel::LoadModule                              ();
use Cpanel::DbUtils                                 ();
use Cpanel::MysqlUtils::MyCnf                       ();
use Cpanel::PasswdStrength::Check                   ();
use Cpanel::MysqlUtils::MyCnf::Basic                ();
use Cpanel::MysqlUtils::Integration                 ();
use Cpanel::MysqlUtils::RemoteMySQL::ProfileManager ();
use Cpanel::MysqlUtils::Version                     ();

use constant NEEDS_ROLE => 'MySQLClient';

=head1 NAME

Whostmgr::API::1::LocalMySQL - API calls to manage the MySQL instance on the localhost.

=head1 SYNOPSIS

    use Whostmgr::API::1::LocalMySQL ();
    Whostmgr::API::1::LocalMySQL::set_root_mysql_password(
        {
            'password' => 'mynewpassword',
        },
        $metadata
    ) or die "something went wrong";

=cut

=head1 Methods

=over 8

=item B<set_root_mysql_password>

Sets the root password on the MySQL instance on the localhost.

B<Input>: Takes two hashrefs:

    * First hashref must contain details about the new password
      The following information is required:

            password - The new password to set for the MySQL root user.

      Optionally, you can pass in:

            update_config - A Boolean value indicating whether or not
                            to update the configuration files after the
                            password is reset.

    * Second hashref is a reference to the metadata.

B<Output>: Returns a hashref containing details about the password set process.
Sets the 'result', 'reason' and 'errors' array in the C<$metadata> hashref accordingly on failure.

Example of returned hash:

    {
        'password_reset'  => 1 or 0,
        'configs_updated' => 1 or 0,
    }

=cut

sub set_local_mysql_root_password {
    my ( $args, $metadata ) = @_;

    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';

    Cpanel::LoadModule::load_perl_module('Cpanel::MysqlUtils::ResetRootPassword');
    my $output;
    try {
        die Cpanel::Exception::create( 'Services::NotInstalled', [ service => 'Local MySQL' ] ) if !Cpanel::DbUtils::find_mysqld();

        die Cpanel::Exception::create( 'RemoteMySQL::RootPasswordResetError', [ 'error' => 'Passwords must be at least 5 characters long' ] ) if length $args->{'password'} < 5;
        Cpanel::PasswdStrength::Check::verify_or_die( 'app' => 'mysql', 'pw' => $args->{'password'} );

        # Ensure all mysql version checks query the local mysql instance
        # and not any active remote mysql profiles.
        local $Cpanel::MysqlUtils::Version::USE_LOCAL_MYSQL = 1;

        # TODO: Try Cpanel::MysqlUtils::RootPassword first as its far safer
        # and will not cause a mysql restart
        my $reset_obj = Cpanel::MysqlUtils::ResetRootPassword->new( 'password' => $args->{'password'} );
        my ( $reset_ok, $reset_message ) = $reset_obj->reset();
        if ( !$reset_ok ) {
            die Cpanel::Exception::create( 'RemoteMySQL::RootPasswordResetError', [ 'error' => $reset_message ] );
        }
        $output->{'password_reset'} = 1;

        my $active_mysql_host = Cpanel::MysqlUtils::MyCnf::Basic::getmydbhost('root') || 'localhost';
        if ( Cpanel::MysqlUtils::MyCnf::Basic::is_local_mysql($active_mysql_host) ) {

            # If we just changed the root password for the localhost, and a 'localhost' profile is active,
            # then we must update the configuration files in order to have a functioning system after the password reset.
            # The user can specify that this not happen by passing 'update_config' = 0 in the API call.
            $args->{'update_config'} //= 1;

            # Update the 'active' profile details to have the new password also.
            my $profile_manager        = Cpanel::MysqlUtils::RemoteMySQL::ProfileManager->new();
            my $active_profile         = $profile_manager->get_active_profile('dont_die');
            my $active_profile_details = $profile_manager->read_profiles()->{$active_profile};

            if ( $active_mysql_host eq $active_profile_details->{'mysql_host'} ) {
                $active_profile_details->{'name'}       = $active_profile;
                $active_profile_details->{'mysql_pass'} = $args->{'password'};
                $profile_manager->create_profile( $active_profile_details, { 'overwrite' => 1 } );
                $profile_manager->mark_profile_as_active($active_profile);
                $profile_manager->save_changes_to_disk();
                $output->{'profile_updated'} = 1;
            }
        }

        if ( $args->{'update_config'} ) {

            # We have simlar code in Cpanel::MysqlUtils::RootPassword that was originally
            # in scripts/mysqlpasswd
            Cpanel::MysqlUtils::MyCnf::update_mycnf(
                user  => 'root',
                items => [
                    {
                        'pass' => $args->{'password'},
                    }
                ],
            );
            Cpanel::MysqlUtils::MyCnf::update_mycnf(
                user       => 'root',
                section    => 'mysqladmin',
                if_present => 1,
                items      => [
                    {
                        'pass' => $args->{'password'},
                    }
                ],
            );
            Cpanel::MysqlUtils::Integration::update_apps_that_use_mysql_in_background();
            $output->{'configs_updated'} = 1;
        }
    }
    catch {
        _handle_failure( $metadata, { 'action' => 'set_root_mysql_password', 'exception' => $_ } );
    };
    return if !$metadata->{'result'};

    return $output;
}

sub _handle_failure {
    my ( $metadata, $opts ) = @_;

    my $locale     = Cpanel::Locale->get_handle();
    my $action     = $opts->{'action'} || 'unknown';
    my $exceptions = ref $opts->{'exception'} eq 'HASH' ? $opts->{'exception'}->{'exceptions'} : [ $opts->{'exception'} ];
    $metadata->{'result'}      = 0;
    $metadata->{'reason'}      = $locale->maketext( 'Failed to perform “[_1]” action. [quant,_2,error,errors] occurred.', $action, scalar @{$exceptions} );
    $metadata->{'error_count'} = scalar @{$exceptions};
    _populate_errors( $metadata, $exceptions );
    return 1;
}

sub _populate_errors {
    my ( $metadata, $exceptions_ar ) = @_;

    $metadata->{'errors'} = [];
    foreach my $error ( @{$exceptions_ar} ) {
        push @{ $metadata->{'errors'} }, Cpanel::Exception::get_string($error);
    }
    return 1;
}

=back

=cut

1;
