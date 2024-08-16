package Cpanel::API::Integration;

# cpanel - Cpanel/API/Integration.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::AdminBin::Call                ();
use Cpanel::Debug                         ();
use Cpanel::Integration::Config           ();
use Cpanel::Exception                     ();
use Cpanel::Locale                        ();
use Cpanel::Transaction::File::JSONReader ();

use Try::Tiny;

## no critic qw(TestingAndDebugging::RequireUseWarnings)
my $locale;
my $logger;

=encoding utf-8

=head1 NAME

Cpanel::API::Integration

=head1 DESCRIPTION

UAPI functions related to Integration.

=cut

=head1 SYNOPSIS

    use Cpanel::API ();

    my $fetch = Cpanel::API::execute(
        'Integration',
        'fetch_url'
        {'app'=>'myapp'}
    );

    my $data = $fetch->data();

    print "Let’s go to $data->{'redirect_url'}";

=cut

=head1 DESCRIPTION

=head2 fetch_url

=head3 Purpose

Returns the URL for the integrated application.  The url may be an autologin endpoint or simply
a generic entry point to the application.

=head3 Arguments

=over

=item 'app': string - The name of the app that was provided when the integration link was created

=back

=head3 Returns

=over

=item A hashref with at least one of the following values which are obtained from the autologin_token_url or user integration config.

=over

=item 'redirect_url': string - The url to direct the user to

=item 'url': string - A fallback url to use when the redirect_url is unspecified

=back

=back

If an error occurs, the function will throw an exception.

=cut

sub fetch_url {
    my ( $args, $result ) = @_;

    my $app    = $args->get_length_required('app');
    my $reader = Cpanel::Transaction::File::JSONReader->new( path => Cpanel::Integration::Config::get_app_config_path_for_user( $Cpanel::user, $app ) );
    my $config = $reader->get_data();
    if ( !$config || !ref $config || ref $config ne 'HASH' ) {

        die _locale()->maketext( 'The system did not find a valid integration configuration for the application “[_1]” for the user “[_2]”.', $app, $Cpanel::user );
    }

    if ( $config->{'autologin_token_url'} ) {
        my ( $ret, $err );
        try {
            $ret = Cpanel::AdminBin::Call::call( 'Cpanel', 'integration_call', 'FETCH_AUTO_LOGIN_URL', { 'app' => $app } );
        }
        catch {
            $err = $_;
        };
        if ( !$err && $ret ) {
            $result->data($ret);
            return 1;
        }
        if ($err) {
            Cpanel::Debug::log_warn( 'The system failed to call “FETCH_AUTO_LOGIN_URL” because of an error: ' . Cpanel::Exception::get_string($err) );
            if ( !$config->{'url'} ) {    # no fallback url
                die _locale()->maketext( 'The system failed to call “[_1]” because of an error: [_2]', 'FETCH_AUTO_LOGIN_URL', Cpanel::Exception::get_string($err) );
            }
        }
    }

    if ( $config->{'url'} ) {
        $result->data( { 'redirect_url' => $config->{'url'} } );
        return 1;
    }
    else {
        die _locale()->maketext( 'The integration configuration file for “[_1]” did not contain a “[_2]” or “[_3]” entry.', $app, 'autologin_token_url', 'url' );
    }
}

sub _locale {
    return ( $locale ||= Cpanel::Locale->get_handle() );
}

our %API = (
    fetch_url => { allow_demo => 1 },
);

1;
