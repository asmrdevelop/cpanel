package Cpanel::API::WebDisk;

# cpanel - Cpanel/API/WebDisk.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

## no critic qw(TestingAndDebugging::RequireUseWarnings)
#use warnings;

require 5.014;

use Try::Tiny;

use Cpanel          ();
use Cpanel::Chdir   ();
use Cpanel::WebDisk ();
use File::Path      ();

use Cpanel::Locale::Lazy 'lh';

our %API = (
    _needs_role    => 'WebDisk',
    _needs_feature => 'webdisk',
);

# TODO: Need to move the api2 code over here eventually

#-------------------------------------------------------------------------------------------------
# Purpose:  This module contains the API calls and support code related to the managing the
# WebDisk users. This code calls into the existing Cpanel::WebDisk module to perform its duties.
#-------------------------------------------------------------------------------------------------

=head1 NAME

Cpanel::API::WebDisk

=head1 DESCRIPTION

UAPI functions related to the management of WebDisk accounts.

=head1 FUNCTIONS

=head2 delete_user

Delete a WebDisk user from the system.

Arguments

  - user    - String - full username for the webdisk account including the <login>@<domain>
  - destroy - Boolean - if truthy, the call will delete the user's folder; otherwise, the user's folder is left alone.

Returns

N/A

=cut

sub delete_user {
    my ( $args, $result ) = @_;
    my ($user) = _get_required_args( $args, [qw(user)] );
    my $destroy = $args->get('destroy');

    # Since we are making direct use of api2 calls for now,
    # we need to simulate the environment, preserve the context
    # in case something else is using it.
    my $context = $Cpanel::context;
    $Cpanel::context = 'webdisk';

    if ($destroy) {
        my @matches = Cpanel::WebDisk::api2_listwebdisks( regex => '^' . quotemeta($user) . '$' );
        if (@matches) {
            my $match   = $matches[0];
            my $homedir = $match->{homedir};

            if ( -d $homedir ) {
                try {

                    # Required to avoid chdir errors when File::Path::rmtree() attempts to chdir back
                    # into the current working directory when it's finished.
                    my $user_dir;
                    if ( $> != 0 ) {
                        $user_dir = Cpanel::Chdir->new( $Cpanel::homedir, quiet => 1 );
                    }

                    # NOTE: remove_tree can die under some conditions or can return errors
                    # in the error array depending on the severity of the issues.
                    File::Path::remove_tree( $homedir, { error => \my $errors } );
                    if (@$errors) {
                        my $messages;
                        for my $error (@$errors) {
                            my ( $file, $message ) = %$error;
                            if ( $file eq '' ) {
                                $messages .= "$message\n";
                            }
                            else {
                                $messages .= "$file: $message\n";
                            }
                        }
                        die $messages;
                    }
                }
                catch {

                    #Restore the context
                    $Cpanel::context = $context;
                    die lh()->maketext( 'The system failed to remove the [asis,WebDisk] user’s files: [_1]', $_ );
                }
            }
        }
    }

    my $ret = Cpanel::WebDisk::api2_delwebdisk( login => $user );
    if ( !$ret ) {
        my $msg = $Cpanel::CPERROR{'webdisk'};
        $result->raw_error( $msg ? $msg : lh()->maketext('The system failed to delete the [asis,WebDisk] account. An unknown error occurred.') );

        #Restore the context
        $Cpanel::context = $context;
        return 0;
    }

    #Restore the context
    $Cpanel::context = $context;
    return 1;
}

sub set_password {
    my ( $args, $result )   = @_;
    my ( $user, $password ) = _get_required_args( $args, [qw(user password)] );
    my $enabledigest = $args->get('enabledigest');

    # Since we are making direct use of api2 calls for now,
    # we need to simulate the environment, preserve the context
    # in case something else is using it.
    my $context = $Cpanel::context;
    $Cpanel::context = 'webdisk';

    my $ret = Cpanel::WebDisk::api2_passwdwebdisk( login => $user, password => $password, enabledigest => $enabledigest );
    if ( !$ret ) {
        my $msg = $Cpanel::CPERROR{'webdisk'};
        $result->raw_error( $msg ? $msg : lh()->maketext('The system failed to set the password for the [asis,Web Disk] account. An unknown error occurred.') );

        #Restore the context
        $Cpanel::context = $context;
        return 0;
    }

    #Restore the context
    $Cpanel::context = $context;
    return 1;
}

sub set_homedir {
    my ( $args, $result )  = @_;
    my ( $user, $homedir ) = _get_required_args( $args, [qw(user homedir)] );
    my ($private) = $args->get(qw(private));

    # Since we are making direct use of api2 calls for now,
    # we need to simulate the environment, preserve the context
    # in case something else is using it.
    my $context = $Cpanel::context;
    $Cpanel::context = 'webdisk';

    my $ret = Cpanel::WebDisk::api2_set_homedir( login => $user, homedir => $homedir, private => $private );
    if ( !$ret ) {
        my $msg = $Cpanel::CPERROR{'webdisk'};
        $result->raw_error( $msg ? $msg : lh()->maketext('The system failed to set the home directory for the [asis,Web Disk] account. An unknown error occurred.') );

        #Restore the context
        $Cpanel::context = $context;
        return 0;
    }
    elsif (@$ret) {
        if ( !$ret->[0]{result} ) {
            my $err = $ret->[0]{reason};
            $result->raw_error( $err ? $err : lh()->maketext('The system failed to set the home directory for the [asis,Web Disk] account. An unknown error occurred.') );

            #Restore the context
            $Cpanel::context = $context;
            return 0;
        }
    }

    #Restore the context
    $Cpanel::context = $context;
    return 1;
}

sub set_permissions {
    my ( $args, $result ) = @_;
    my ( $user, $perms )  = _get_required_args( $args, [qw(user perms)] );

    # Since we are making direct use of api2 calls for now,
    # we need to simulate the environment, preserve the context
    # in case something else is using it.
    my $context = $Cpanel::context;
    $Cpanel::context = 'webdisk';

    my $ret = Cpanel::WebDisk::api2_set_perms( login => $user, perms => $perms );
    if ( !$ret ) {
        my $msg = $Cpanel::CPERROR{'webdisk'};
        $result->raw_error( $msg ? $msg : lh()->maketext('The system failed to set the permissions for the [asis,Web Disk] account. An unknown error occurred.') );

        #Restore the context
        $Cpanel::context = $context;
        return 0;
    }
    elsif (@$ret) {
        if ( !$ret->[0]{result} ) {
            my $err = $ret->[0]{reason};
            $result->raw_error( $err ? $err : lh()->maketext('The system failed to set the permissions for the [asis,Web Disk] account. An unknown error occurred.') );

            #Restore the context
            $Cpanel::context = $context;
            return 0;
        }
    }

    #Restore the context
    $Cpanel::context = $context;
    return 1;
}

sub _get_required_args {
    my ( $args, $required_ar ) = @_;
    my @found;
    for my $required (@$required_ar) {
        my $value = $args->get($required);
        if ( !length($value) ) {
            die lh()->maketext( 'You must specify the “[_1]” parameter.', $required ) . "\n";
        }
        push @found, $value;
    }
    return @found;
}

1;
