
# cpanel - Cpanel/Transport/Files/GoogleDrive/AuthHandler.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Transport::Files::GoogleDrive::AuthHandler;

use strict;
use warnings;

use Try::Tiny;

use OAuth::Cmdline::CustomFile ();

use Cpanel::ConfigFiles                                   ();
use Cpanel::Daemonizer::Tiny                              ();
use Cpanel::DataStore                                     ();
use Cpanel::Hostname                                      ();
use Cpanel::Rand::Get                                     ();
use Cpanel::Transport::Files::GoogleDrive::CredentialFile ();

=head1 NAME

Cpanel::Transport::Files::GoogleDrive::AuthHandler

=head1 SYNOPSIS

This module handles issues relating to the generation
of authorization credentials for the GoogleDrive transport.

=head1 DESCRIPTION

Functionality relating to generating GoogleDrive authorization credentials.

=head1 SUBROUTINES

=head2 write_oauth_params_to_temp_file

Given a client ID and secret, write all the params for an
OAuth::Cmdline::CustomFile to a temporary file.

=cut

sub write_oauth_params_to_temp_file {
    my ( $temp_file_name, $client_id, $client_secret ) = @_;

    my $hostname = Cpanel::Hostname::gethostname();

    my %oauth_info = (
        'client_id'     => $client_id,
        'client_secret' => $client_secret,
        'login_uri'     => "https://accounts.google.com/o/oauth2/auth",
        'token_uri'     => "https://accounts.google.com/o/oauth2/token",
        'scope'         => "https://www.googleapis.com/auth/drive.file",
        'access_type'   => "offline",
        'local_uri'     => "https://$hostname:2087/googledriveauth",
        'custom_file'   => Cpanel::Transport::Files::GoogleDrive::CredentialFile::credential_file_from_id($client_id),
    );

    Cpanel::DataStore::store_ref( $temp_file_name, \%oauth_info, ['0600'] );

    return;
}

=head2 generate_oauth_from_temp_file

Read all the parameters from our temporary file and
generate an OAuth::Cmdline::CustomFile object.

=cut

sub generate_oauth_from_temp_file {
    my ($temp_file_name) = @_;

    my $oauth_params = Cpanel::DataStore::load_ref($temp_file_name);
    if ( !$oauth_params ) {
        die "Unable to load $temp_file_name";
    }

    return OAuth::Cmdline::CustomFile->new(%$oauth_params);
}

=head2 generate_google_oauth_uri_and_save_params

Given a client ID and secret, write all the params for an
OAuth::Cmdline::CustomFile to a temporary file.
And, return the URI needed to initiate and OAuth token request.

=cut

sub generate_google_oauth_uri_and_save_params {
    my ( $client_id, $client_secret ) = @_;

    my $state = Cpanel::Rand::Get::getranddata( 64, [ 0 .. 9, 'A' .. 'Z', 'a' .. 'z' ] );

    my $temp_file_name = $Cpanel::ConfigFiles::GOOGLE_AUTH_TEMPFILE_PREFIX . $state;

    write_oauth_params_to_temp_file( $temp_file_name, $client_id, $client_secret );

    my $oauth_obj = generate_oauth_from_temp_file($temp_file_name);

    # Make sure that these temp files don't accumulate
    # Normally the temp file would be deleted when generate_credential_file is called
    # as a result of the google redirect when the authentication ritual is complated
    # however, if the user does not go through with it, we do not want the file to remain
    Cpanel::Daemonizer::Tiny::run_as_daemon(
        sub {
            # Wait 30 minutes - the file should have served its purpose well before that
            sleep 30 * 60;
            unlink $temp_file_name;
        }
    );

    # Adding prompt=concent allows reuse of older credentials
    return $oauth_obj->full_login_uri() . "&prompt=consent&state=$state";
}

=head2 generate_credential_file

Given the special code returned from google,
Generate an OAuth::Cmdline::CustomFile from the tempfile,
have it generate the OAuth tokens from the code, and
cache the OAuth tokens to the credentials file.

=cut

sub generate_credential_file {
    my ( $code, $state ) = @_;

    if ( $state !~ /^\w+$/ ) {
        print "Invalid state parameter\n";
        return;
    }

    my $temp_file_name = $Cpanel::ConfigFiles::GOOGLE_AUTH_TEMPFILE_PREFIX . $state;

    if ( !-f $temp_file_name ) {
        print "File $temp_file_name does not exist\n";
        return;
    }

    my $oauth_obj = generate_oauth_from_temp_file($temp_file_name);

    unlink $temp_file_name;

    my ( $rc, $message ) = ( 1, "Success" );

    try {
        $oauth_obj->tokens_collect($code);
    }
    catch {
        $rc      = 0;
        $message = $_;
    };

    return ( $rc, $message );
}

1;
