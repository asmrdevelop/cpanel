package Cpanel::OAuth2;

# cpanel - Cpanel/OAuth2.pm                        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use warnings;
use strict;

use Carp ();

use Cpanel::LoadModule              ();
use Cpanel::Config::Contact         ();
use Cpanel::Config::LoadConfig      ();
use Cpanel::LoadFile                ();
use Cpanel::CpKeyClt::SysId         ();
use Whostmgr::TicketSupport::Server ();

our $OVERRIDE_DIR = '/var/cpanel/oauth2';

sub get_oauth2_config {    ## no critic(Subroutines::ProhibitExcessComplexity)
    my $provider = shift;

    # make sure we have a provider
    if ( !$provider ) {

        # attempt to find the provider from the configured file, default to the cpanel provider#
        $provider = Cpanel::LoadFile::loadfile("${OVERRIDE_DIR}/provider") || 'cpanel';
        chomp $provider;
    }
    Carp::croak "[ARGUMENT] provider is not valid: $provider"
      if $provider !~ m/^[a-z0-9]+/;

    my %config;

    my $base_config = "/usr/local/cpanel/etc/oauth2/${provider}.conf";
    if ( -f $base_config ) {
        Cpanel::Config::LoadConfig::loadConfig( $base_config, \%config, undef, undef, undef, 1, { 'nocache' => 1 } )
          or die "could not load base config: $base_config";
    }

    # account.cpanel.net API endpoints
    $config{'auth_endpoint'}     ||= Whostmgr::TicketSupport::Server::make_account_url('/oauth2/auth/login');
    $config{'validate_endpoint'} ||= Whostmgr::TicketSupport::Server::make_account_url('/oauth2/auth/validate_token');

    # tickets.cpanel.net API endpoints
    $config{'API_accessips'}                         ||= Whostmgr::TicketSupport::Server::make_tickets_url('/json-api/access-ips');
    $config{'API_createstubticket'}                  ||= Whostmgr::TicketSupport::Server::make_tickets_url('/json-api/tickets/create-stub-ticket');
    $config{'API_gettechnicalsupportagreementurl'}   ||= Whostmgr::TicketSupport::Server::make_tickets_url('/json-api/tickets/get-technical-support-agreement-url');
    $config{'API_logentry'}                          ||= Whostmgr::TicketSupport::Server::make_tickets_url('/json-api/tickets/log-entry');
    $config{'API_opentickets'}                       ||= Whostmgr::TicketSupport::Server::make_tickets_url('/json-api/tickets/open-tickets');
    $config{'API_recordserverdetailsandfetchsshkey'} ||= Whostmgr::TicketSupport::Server::make_tickets_url('/json-api/tickets/record-server-details-and-fetch-ssh-key');
    $config{'API_serverkey'}                         ||= Whostmgr::TicketSupport::Server::make_tickets_url('/json-api/tickets/server-key');
    $config{'API_supportagreementapprovalstatus'}    ||= Whostmgr::TicketSupport::Server::make_tickets_url('/json-api/tickets/support-agreement-approval-status');
    $config{'API_sshtest'}                           ||= Whostmgr::TicketSupport::Server::make_tickets_url('/json-api/tickets/ssh-test');
    $config{'API_verify'}                            ||= Whostmgr::TicketSupport::Server::make_tickets_url('/json-api/verify-header');
    $config{'API_supportinfo'}                       ||= Whostmgr::TicketSupport::Server::make_tickets_url('/json-api/support-info');

    # verify hostname by default
    $config{'ssl_args'}->{'verify_hostname'} = 1;

    # No verify for testing purposes
    if ( -f '/var/cpanel/no_verify_SSL' ) {
        $config{'ssl_args'}->{'verify_hostname'} = 0;
    }

    my $override_config = "${OVERRIDE_DIR}/${provider}.conf";
    if ( -f $override_config ) {

        Cpanel::Config::LoadConfig::loadConfig( $override_config, \%config, undef, undef, undef, 1, { 'nocache' => 1 } )
          or die "could not load override config: $override_config";
    }

    # if no keys came back, then we had no configs or empty ones #
    die "no configuration values for provider: $provider"
      if !keys %config;

    # pull out ssl_args into a sub-member #
    foreach my $key ( keys %config ) {
        next if $key !~ m/^ssl_arg_(.+)$/;
        $config{'ssl_args'}->{$1} = delete $config{$key};
    }

    # pull out extras into a sub-member #
    foreach my $key ( keys %config ) {
        next if $key !~ m/^extra_(.+)$/;
        $config{'extras'}->{$1} = delete $config{$key};
    }

    my $server_contact = Cpanel::Config::Contact::get_server_contact();
    if ($server_contact) {
        $config{'extras'}{'email'} ||= $server_contact;
    }

    # default values for some stuff #
    $config{'redirect_uri'}  ||= '/unprotected/oauth2callback.html';
    $config{'response_type'} ||= 'token';
    $config{'scopes'}        ||= [];
    $config{'client_id'}     ||= substr( Cpanel::CpKeyClt::SysId::getsysid(), -16 ) || undef;

    # custom oauth2 auth endpoint parameters
    $config{'extras'}{'client_name'}       ||= 'cPanel & WHM';
    $config{'extras'}{'client_identifier'} ||= 'cpanel';

    return \%config;
}

sub validate_code {
    my ( $p_code, $p_request_data ) = @_;

    Cpanel::LoadModule::load_perl_module('Cpanel::JSON::HttpRequest');

    # we need to validate this code and get a token #

    # read oauth2 configuration #
    my $oauth2_config = get_oauth2_config();
    my $ssl_args      = defined $oauth2_config->{'ssl_args'} ? $oauth2_config->{'ssl_args'} : {};

    # validate request #
    my %request = (
        %{ defined $p_request_data ? $p_request_data : {} },
        'code' => $p_code,

        #'authorization_code' => 'authorization_code',
        'client_id'  => $oauth2_config->{'client_id'},
        'client_key' => $oauth2_config->{'client_key'}
    );

    my $validate_endpoint = $oauth2_config->{'validate_endpoint'};
    my ( $response, $status ) = Cpanel::JSON::HttpRequest::make_json_request( $validate_endpoint, \%request, 'ssl_args' => $ssl_args, 'submitas' => 'POST' );

    return $response, $status;
}

1;
