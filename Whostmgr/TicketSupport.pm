package Whostmgr::TicketSupport;

# cpanel - Whostmgr/TicketSupport.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Carp                    ();
use Cpanel::Debug           ();
use Cpanel::Exception       ();
use Cpanel::CpKeyClt::SysId ();
use Cpanel::Hostname        ();
use Cpanel::JSON            ();
use Cpanel::NAT             ();
use Cpanel::SSH::Port       ();

use Cpanel::Locale::Lazy 'lh';

sub _prep_headers_for_remote_api {
    my $p_oauth2_config = shift;
    my $api_version     = shift;

    $api_version = 'V1' if !defined $api_version;
    require Whostmgr::TicketSupport::Token;

    # get support ID as it's our client_id #
    my $support_id  = substr( Cpanel::CpKeyClt::SysId::getsysid(), -16 ) || undef;
    my $token_value = Whostmgr::TicketSupport::Token->new()->value()
      or die Cpanel::Exception->create('The [asis,cp_ticket_system_token] does not exist in the session data.');

    # different style headers #
    my %headers;
    if ( $api_version eq 'V3' ) {
        $headers{'Authorization'} = "Bearer " . $token_value;
    }
    else {
        if ( ( $p_oauth2_config->{'API_callstyle'} || 'JSON_HEADER' ) eq 'JSON_HEADER' ) {
            $headers{'JSON-Auth'} = Cpanel::JSON::Dump(
                {
                    'client_id' => $p_oauth2_config->{'client_id'} || $support_id,
                    'token'     => $token_value,
                }
            );
        }
        else {
            $headers{'X-Auth-ID'}    = $p_oauth2_config->{'client_id'} || $support_id;
            $headers{'X-Auth-Token'} = $token_value;
        }
    }

    return \%headers;
}

sub _do_basic_api_call {

    my ( $p_api, $api_version, $p_args, $p_data_ref, %p_options ) = @_;

    # options #
    my $expected_any_status = $p_options{'expected_any_status'};
    $expected_any_status = 0
      if !defined $expected_any_status;

    # load config #
    require Cpanel::OAuth2;
    my $oauth2_config = Cpanel::OAuth2::get_oauth2_config();
    my $ssl_args      = defined $oauth2_config->{'ssl_args'} ? $oauth2_config->{'ssl_args'} : {};

    # build request #
    my $url = $oauth2_config->{$p_api};

    Carp::croak "[STATE] $p_api was not found in the configuration!"
      if !$url;

    if ( $p_options{'url_post'} ) {

        # add additions to the URL #
        $url .= $p_options{'url_post'};
    }
    my $headers = _prep_headers_for_remote_api( $oauth2_config, $api_version );

    if ( $api_version eq 'V3' ) {

        # need to add a content header here for API V3
        $headers->{'Content-Type'} = 'application/vnd.cpanel.tickets-v3+json';
    }

    # make the call #
    require Cpanel::JSON::HttpRequest;
    my ( $response, $status ) = Cpanel::JSON::HttpRequest::make_json_request( $url, $p_args, 'ssl_args' => $ssl_args, 'headers' => $headers, 'method' => $p_options{'method'}, json_exception_class => 'TicketSupport::JsonApi' );
    if ( ( !$expected_any_status && 200 != $status ) || ref $response ne ref( {} ) ) {
        my $tmpreason = 'undef';
        $tmpreason = $response->{'message'}
          if ref $response eq ref( {} ) && $response->{'message'};
        Cpanel::Debug::log_warn( "No response, or an invalid one, came back from the remote server: STATUS=$status, REF=" . ref($response) . qq{, URL=$url, REASON="$tmpreason"} );
        return defined $response && ref $response eq ref( {} ) ? $response : undef, $status, $tmpreason;
    }

    # common sanity... only for sane responses #
    if ( $status =~ m/^2/ ) {
        return undef, $status, "data member is not $p_data_ref: undef"
          if ref $response ne 'HASH';
        return $response, 555, "data member is not $p_data_ref: " . ref( $response->{'data'} )
          if ref $response->{'data'} ne $p_data_ref;
    }

    # return full response, status and specific message string, caller convenience #
    return $response, $status, $response->{'message'};
}

sub access_ips {

    # see if we can deliver a cached copy of the access_ips #
    require Whostmgr::TicketSupport::DataStore;
    my $store             = Whostmgr::TicketSupport::DataStore->new();
    my $cached_access_ips = $store->get('access_ips');
    if ( ref $cached_access_ips eq 'HASH' && $cached_access_ips->{'cached_at'} && time() - $cached_access_ips->{'cached_at'} < 120 ) {
        $store->abort();
        return $cached_access_ips->{'data'};
    }

    my ( $response, $status ) = _do_basic_api_call( 'API_accessips', 'V1', undef, ref [], 'method' => 'GET' );
    return undef if $status != 200;

    # validate we have everything #
    if ( 200 != $response->{'status'} ) {

        # something... else? #
        Cpanel::Debug::log_warn( "No response, or an invalid one, came back from remote access_ips: JSON_STATUS=$response->{'status'}, REF=" . ref( $response->{'data'} ) );
        return undef;
    }

    # update cache #
    $store->set( 'access_ips', { 'cached_at' => time(), 'data' => $response->{'data'} } )->cleanup();

    return $response->{'data'};
}

sub get_authorization_information {
    my ( $p_ticket_id, $p_server_num, $p_secure_id, %p_options ) = @_;

    # sanity check #
    Carp::croak '[ARGUMENT] missing ticket_id argument'
      if !defined $p_ticket_id;
    Carp::croak '[ARGUMENT] missing server_num argument'
      if !defined $p_server_num;

    my %content = (
        'ticket_id'              => $p_ticket_id,
        'server_num'             => $p_server_num,
        'secure_id'              => $p_secure_id,
        'hostname'               => Cpanel::Hostname::gethostname(),
        'shorthostname'          => Cpanel::Hostname::shorthostname(),
        'ssh_port'               => Cpanel::SSH::Port::getport(),
        'ssh_user'               => $p_options{'ssh_user'}               || 'root',
        'root_escalation_method' => $p_options{'root_escalation_method'} || '',
        $p_options{'wheel_password'} ? ( 'wheel_pass' => $p_options{'wheel_password'} ) : (),
    );

    my ( $response, $status ) = _do_basic_api_call( 'API_recordserverdetailsandfetchsshkey', 'V3', \%content, 'HASH', 'expected_any_status' => 1, 'method' => 'POST' );
    return undef, $status if $status != 200;

    # validate we have everything (ie data is correct) #
    my $servers = $response->{'data'};

    # validate we have everything #
    if ( 200 != $status ) {

        # something... else? #
        Cpanel::Debug::log_warn( "No response, or an invalid one, came back from remote get_authorization_information: JSON_STATUS=$response->{'status'}, REF=" . ref( $servers->{'data'} ) );
        return undef, $response->{'status'};
    }

    # normalize for our return through the cPanel XML-API #
    #my $data = $servers->{$p_server_num};  # we're already collapsing this on the ticket side. Delete?
    return {
        'server_name'            => $servers->{'server_name'},
        'ssh_username'           => $servers->{'ssh_username'},
        'ssh_ip'                 => $servers->{'ssh_ip'},
        'ssh_port'               => $servers->{'ssh_port'} || ( getservbyname( 'ssh', 'tcp' ) )[2],
        'ssh_user'               => $servers->{'ssh_user'},
        'ssh_key'                => $servers->{'ssh_public_key'},
        'root_escalation_method' => $servers->{'root_escalation_method'},
        'whm_ip'                 => $servers->{'whm_ip'}
    }, $status;
}

=head1 NAME

Whostmgr::TicketSupport

=head2 remote_authorizations_list(USER, MATCHERS)

List the tickets on the ticket system that have server data.

=head3 Parameters

 USER:     string          - user we want the list for.
 MATCHERS: array of regexp - optional, list of patterns matchers for the ssh keys associated with a server.

=head3 Returns

  hashref - where each key is a ticket id and the value is a hash ref as follows:

    servers - hashref - where each key is a number 1 to n and the value of that key is the following server data as a hash ref:

      server_name  - string - name of the server
      whm_ip       - string - ip address hosting whm on that server.
      ssh_ip       - string - ip address hosting ssh on that server.
      ssh_username - string - username used to log into ssh.

    ticket_subject - string - subject line of the ticket
    ticket_id      - number - id for the ticket, same as the key of the parent.
    exception      - string - optional, if provided it holds information about why server information could not be retrieved.

=cut

sub remote_authorizations_list {
    my ( $p_user,  $p_matchers )     = @_;
    my ( $tickets, $tickets_status ) = _do_basic_api_call( 'API_opentickets', 'V1', undef, ref [], 'method' => 'GET' );

    return undef, $tickets_status if $tickets_status != 200;

    # validate we have everything #
    if ( 200 != $tickets->{'status'} ) {

        # something... else? #
        Cpanel::Debug::log_warn( "No response, or an invalid one, came back from remote remote_authorizations_list: JSON_STATUS=$tickets->{'status'}, REF=" . ref( $tickets->{'data'} ) );
        return undef, $tickets->{'status'};
    }

    # now get data for each ticket #
    my %auths;
    foreach my $ticket ( @{ $tickets->{data} } ) {
        my $ticket_id = $ticket->{ticket_id};

        my ( $servers, $exception ) = ( {}, undef );

        if ( !$ticket->{servers} ) {

            # request all servers for this ticket #
            my ( $serverkeys, $serverkeys_status ) = eval { _do_basic_api_call( 'API_serverkey', 'V1', undef, 'HASH', 'expected_any_status' => 1, 'url_post' => "/$ticket_id", 'method' => 'GET' ) };
            if ( $exception = $@ ) {
                if ( $exception->isa('Cpanel::Exception::TicketSupport::JsonApi')
                    && 404 == $exception->get('status') ) {

                    # No server data found, just leave it empty
                    $serverkeys_status = 404;
                    $exception         = undef;    # We don't need this in this case.
                }
                else {
                    Cpanel::Debug::log_warn("Exception came back from remote API_serverkey: $exception");
                }
            }

            # if no server data for the ticket, move on #
            if ( 200 == $serverkeys_status ) {

                # Use the server data
                $servers = $serverkeys->{data};
            }
            elsif ( 404 != $serverkeys_status ) {

                # No server data found, just leave it empty
                $servers = {};
            }
        }
        else {
            $servers = delete $ticket->{servers};
        }

        # copy the non-server keys into the auth #
        my $auth = { map { $_, $ticket->{$_} } keys %{$ticket} };
        if ($exception) {
            $auth->{exception} = _format_exception($exception);
        }

        foreach my $server_num ( sort keys %{$servers} ) {

            my $server = $servers->{$server_num};

            # filtering #
            next if defined $p_user && $server->{'ssh_username'} ne $p_user;
            if ( defined $p_matchers ) {

                # Generate a fake rsa key with the same email as the tickets rsa key
                my $comment = "ssh-rsa AABADF00D+ ${ticket_id}_server_${server_num}\@cpanel.net_" . time();
                next if defined $p_matchers && !grep { $comment =~ $_ } @{$p_matchers};
            }

            # fixup SSH port if needed #
            $server->{'ssh_port'} ||= ( getservbyname( 'ssh', 'tcp' ) )[2];

            # data for the server #
            my $server_data = {
                'server_name'  => $server->{'server_name'},
                'ssh_username' => $server->{'ssh_username'},
                'ssh_ip'       => $server->{'ssh_ip'},
                'ssh_port'     => $server->{'ssh_port'},
                'whm_ip'       => $server->{'whm_ip'},
            };

            $server_data->{'root_escalation_method'} = $server->{'root_escalation_method'}
              if $server->{'ssh_username'} ne 'root';

            $auth->{'servers'}->{$server_num} = $server_data;
        }

        # add it to the list
        $auths{$ticket_id} = $auth;

    }

    # return auths, and we were successful, or at least we didn't explode #
    return \%auths, 200;
}

sub _format_exception {
    my $exception = shift;
    if ( $exception->can('get_string') ) {
        return $exception->get_string();
    }
    return "$exception";    # stringify it
}

sub update_agreement_approval {
    my (%p_options) = @_;
    my ( $response, $status ) = _do_basic_api_call( 'API_supportagreementapprovalstatus', 'V3', { version => $p_options{version} }, 'HASH', 'method' => 'POST' );
    return $response, $status;
}

sub log_entry {
    my ( $p_ticket_id, $p_server_num, $p_event_type, %p_options ) = @_;

    # build request #
    my %req = (
        'ticket_id'  => $p_ticket_id,
        'server_num' => $p_server_num,
        'event_type' => $p_event_type,
        %{ $p_options{'extras'} || {} }
    );

    my ( $response, $status ) = _do_basic_api_call( 'API_logentry', 'V1', \%req, 'HASH', 'expected_any_status' => 1, 'method' => 'POST' );
    return ( 0, $status ) if 201 != $status;

    # make sure we got a test_id back #
    if ( 201 != $response->{'status'} ) {
        Cpanel::Debug::log_warn("Unexpected response came back from log-entry API: STATUS=$status");
        return 0, $response->{'status'};
    }

    # good to go! #
    return 1, 201;
}

sub connection_test_start {
    my ( $p_ticket_id, $p_server_num ) = @_;

    my ( $response, $status ) = _do_basic_api_call( 'API_sshtest', 'V1', { 'ticket_id' => $p_ticket_id, 'server_num' => $p_server_num }, 'HASH', 'expected_any_status' => 1 );
    return undef, $status, ref($response) eq ref( {} ) ? $response->{'message'} : '' if 200 != $status;

    # make sure we got a test_id back #
    if ( 200 != $response->{'status'} || !$response->{'data'}->{'test_id'} ) {
        Cpanel::Debug::log_warn( "No 'test_id' came back from ssh-test API: STATUS=$status, REF=" . ref( $response->{'data'} ) );
        return undef, 500, ref($response) eq 'HASH' ? $response->{'message'} : '';
    }

    return $response->{'data'}->{'test_id'}, $status, $response->{'message'};
}

sub connection_test_result {
    my $p_test_id = shift;

    my ( $response, $status ) = _do_basic_api_call( 'API_sshtest', 'V1', undef, 'HASH', 'url_post' => "/${p_test_id}", 'method' => 'GET' );
    return undef, $status if 200 != $status && 202 != $status;

    return '__TESTING__', $status
      if 202 == $status;

    # find out if we got all success #
    foreach my $server ( keys %{ $response->{'data'} } ) {

        # return this specific error, it's a 200 as we made a valid request, the test just failed #
        return $response->{'data'}->{$server}->{'result'}, 200, $response->{'message'}
          if $response->{'data'}->{$server}->{'result'} ne 'SUCCESS';
    }

    # assume success if we didn't catch above! #
    return 'SUCCESS', 200, $response->{'message'};
}

sub local_authorizations_list {
    my ( $p_user, $p_matchers, $p_datastore ) = @_;

    # NOTE: this is currently REALLY slow and bad and needs to be fixed #
    # a replacement mapping is in the works but may not get in by demo time #

    # default to a sane search matcher #
    $p_matchers = [qr/\s+\w{3,64}_server_\w{1,64}\@cpanel.net_\d+$/]
      if !defined $p_matchers || !@{$p_matchers};

    # figure out all the users to search #
    my $users;
    if ( defined $p_user ) {
        $users = [$p_user];
    }
    else {
        $users = defined $p_datastore ? $p_datastore->get('users') : ['root'];
    }

    # enumerate the keys from all the relevent users #
    my %tickets;
    my %checked_homedirs;
    require Cpanel::SSH;
    foreach my $user ( @{$users} ) {

        # prevent checking duplicate users #
        my $user_homedir = Cpanel::SSH::_getsshdir($user);
        next if !$user_homedir;
        next if defined $checked_homedirs{$user_homedir};
        $checked_homedirs{$user_homedir} = 1;

        # find all relavent keys #
        my ( $keys, $warnings ) = Cpanel::SSH::_listkeys( 'user' => $user, 'private' => 0, 'public' => 1 );
        foreach my $key ( @{$keys} ) {

            # check against all matchers #
            next if @{$p_matchers} != grep { $key->{'text'} =~ $_ } @{$p_matchers};

            # make sure we can parse the key text #
            next if $key->{'text'} !~ m/\s+(\w{3,64})_server_(\w{1,64})\@cpanel.net_\d+/;

            # see if we can get meta data for this server #
            my $server_key    = "$1_$2_${user}";
            my $ticket_list   = defined $p_datastore ? $p_datastore->get('tickets') : {};
            my $cached_server = $ticket_list->{$1}->{'servers'}->{$server_key} || {};

            # Fill in the ssh ip if missing
            if ( !$cached_server->{ssh_ip} ) {
                require Cpanel::DIp::MainIP;
                my $server_internal_ip = Cpanel::DIp::MainIP::getmainserverip();
                my $server_external_ip = Cpanel::NAT::get_public_ip($server_internal_ip);
                $cached_server->{ssh_ip} = $server_external_ip;
            }

            # Fill in the ssh port if missing
            if ( !$cached_server->{ssh_port} ) {
                $cached_server->{ssh_port} = Cpanel::SSH::Port::getport();
            }

            $tickets{$1}->{'servers'}->{$2} = {
                %{$cached_server},
                'ssh_username' => $user,
                'auth_time'    => $key->{'mtime'}
            };
        }
    }

    return \%tickets;
}

sub create_stub_ticket {

    require Cpanel::DIp::MainIP;
    my $server_internal_ip = Cpanel::DIp::MainIP::getmainserverip();
    my $server_external_ip = Cpanel::NAT::get_public_ip($server_internal_ip);
    require Cpanel::UUID;

    my $content = {
        'support_access_id' => substr( Cpanel::CpKeyClt::SysId::getsysid(), -16 ),
        'server_ip'         => $server_external_ip,
        'hostname'          => Cpanel::Hostname::gethostname(),
        'shorthostname'     => Cpanel::Hostname::shorthostname(),
        'ssh_port'          => Cpanel::SSH::Port::getport(),
        'ssh_username'      => 'root',
        'ssh_ip'            => $server_external_ip,
        'reference_id'      => uc Cpanel::UUID::random_uuid(),
        'source'            => 'WHM',
    };

    my ( $response, $status ) = _do_basic_api_call( 'API_createstubticket', 'V3', $content, 'HASH', 'expected_any_status' => 1, 'method' => 'POST' );

    return $response;
}

sub get_support_agreement {

    ####
    # 1. Determine where the latest version of the Technical Support Agreement is kept.
    #

    my ( $response, $status ) = _do_basic_api_call( 'API_gettechnicalsupportagreementurl', 'V3', undef, 'HASH', 'expected_any_status' => 1, 'method' => 'GET' );

    my $url = $response->{data}{json_url} || die q{WHM could not find the Technical Support Agreement URL in the response from the ticket system API.};

    ####
    # 2. Determine the last time this user accepted the Technical Support Agreement, if ever.
    #

    my ( $ever_accepted, $last_accepted_timestamp, $version_accepted );

    # If this query fails for some reason, it will be treated the same as if they had never accepted the agreement.
    eval {
        ( $response, $status ) = _do_basic_api_call( 'API_supportagreementapprovalstatus', 'V3', undef, 'HASH', 'expected_any_status' => 1, 'method' => 'GET' );
        ( $ever_accepted, $last_accepted_timestamp, $version_accepted ) = @{ $response->{data} }{qw(agreed timestamp version)};
    };
    if ( my $exception = $@ ) {
        Cpanel::Debug::log_info("Non-fatal error: Failed to retrieve technical support agreement approval status: $exception");
    }

    ####
    # 3. Fetch the latest version of the Technical Support Agreement JSON data, which includes the actual text.
    #

    require Cpanel::HTTP::Tiny::FastSSLVerify;                                       #FIXME: cache this
    my $agreement_response = Cpanel::HTTP::Tiny::FastSSLVerify->new()->get($url);    # no authentication required

    die lh()->maketext( qq{The system received an unexpected status while retrieving the [asis,Technical Support Agreement]: [_1]}, $agreement_response->{status} ) . "\n"
      if 200 != $agreement_response->{status};

    ####
    # 4. Validate the Technical Support Agreement data
    #

    my $agreement_info = Cpanel::JSON::Load( $agreement_response->{content} );
    for my $required (qw(version create_date view_url download_url title body)) {
        defined( $agreement_info->{$required} ) or die "Required key $required is missing from Technical Support Agreement info.";
    }

    ####
    # 5. Add in fields that weren't part of the original JSON data, and return this structure.
    #    This includes 'accepted', which indicates whether the latest version of the agreement
    #    has already been accepted. If true, then the caller can skip displaying the agreement
    #    text.
    #

    if (   $ever_accepted
        && $last_accepted_timestamp
        && $agreement_info->{create_date}
        && $last_accepted_timestamp > $agreement_info->{create_date}
        && $version_accepted eq $agreement_info->{version} ) {
        $agreement_info->{accepted}      = 1;
        $agreement_info->{accepted_date} = $last_accepted_timestamp;
    }
    else {
        $agreement_info->{accepted}      = 0;
        $agreement_info->{accepted_date} = undef;
    }

    for my $timestamp_name (qw(create_date accepted_date)) {
        $agreement_info->{"${timestamp_name}_human"} =
          $agreement_info->{$timestamp_name}
          ? lh()->maketext( '[datetime,_1,date_format_short]', $agreement_info->{$timestamp_name} )
          : undef;
    }

    return $agreement_info;
}

=head1 NAME

Whostmgr::TicketSupport::get_support_info

=head2 Description

Queries manage2 and returns support information based on the current public facing ip.

Must be authenticated through oauth for this call to work.

=head2 Parameters

  None.

=head2 Returns

  hashref - with the following keys:

    company_id - integer - A number that represents the company associated with the licensed IP address.
    tech_contact_email - string - The contact email address for the company's technical support.
    ip - string - The IP address of the retrieved information.
    company_name - string - The human-readable company name associated with the submitted IP address.
    pub_support_contact - string - The URL to the company's support resources, optionally set up for Partner NOC.
    pub_tech_contact    - string - The URL to the company's general tech support resources. Generally preferred to pub_support_contact.
    hostname - string - The hostname of the server as recorded in the license database.
    logo_url - string - The optional URL to the company's brand image file on the partner website.
    pub_tech_contact - string - The optional URL to the company's technical support resources.
    gets_direct_support - bool - Whether the IP address's owner primary support is cPanel, Inc
    has_compatibility_info - bool - Whether the response contains the server's compatibility information.
    distro - string - The server's operating system retrieved during the last license check.
    distro_supported - string - Whether cPanel Support provides assistance for the retrieved operating system.
    arch - string - The server's CPU architecture retrieved at the last license check.
    arch_supported - string - Whether cPanel Support provides assistance with the retrieved CPU architecture.
    has_company_info - bool -  Whether the response contains the company information associated with the licensed IP address.


=cut

sub get_support_info {
    require Cpanel::DIp::MainIP;
    my $ip = Cpanel::NAT::get_public_ip( Cpanel::DIp::MainIP::getmainserverip() || undef );
    my ( $response, $status ) = _do_basic_api_call( 'API_supportinfo', 'V3', undef, 'HASH', 'expected_any_status' => 1, 'method' => 'GET', url_post => "/$ip" );
    $response->{error} = "Failed to retrieve support information for $ip" if $status != 200;
    return $response;
}

1;
