package Whostmgr::API::1::TicketSupport;

# cpanel - Whostmgr/API/1/TicketSupport.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

Whostmgr::API::1::TicketSupport

=head1 DESCRIPTION

This is the public-facing API for the "Grant cPanel Support Access" feature in WHM.
The only expected caller is the Grant cPanel Support Access UI itself, but
third-party developers could theoretically write their own applications that call
this API if needed.

Note that the parameters and return values documented here are for the API itself,
not for direct callers of the API handler functions. (Direct callers need to follow
the usual xml-api conventions for simulating an xml-api query.)

=cut

use strict;
use warnings;

use Carp ();

use Cpanel::LoadModule ();
use Cpanel::Debug      ();
use Cpanel::Binary     ();
use Cpanel::Binaries   ();
use Cpanel::Locale::Lazy 'lh';
use Cpanel::SafeDir::MK        ();
use Cpanel::SafeFile           ();
use Cpanel::StringFunc::Trim   ();
use Cpanel::Validate::Username ();
use Cpanel::NAT                ();
use Cpanel::OS                 ();

use constant NEEDS_ROLE => {
    ticket_create_stub_ticket                => undef,
    ticket_get_support_agreement             => undef,
    ticket_grant                             => undef,
    ticket_list                              => undef,
    ticket_remove_closed                     => undef,
    ticket_revoke                            => undef,
    ticket_ssh_test                          => undef,
    ticket_ssh_test_start                    => undef,
    ticket_update_service_agreement_approval => undef,
    ticket_validate_oauth2_code              => undef,
    ticket_whitelist_check                   => undef,
    ticket_whitelist_setup                   => undef,
    ticket_whitelist_unsetup                 => undef,
    ticket_get_support_info                  => undef,
};

my $gl_ticket_log      = '/var/cpanel/logs/supportauth/audit.log';
my $gl_ticket_log_path = '/var/cpanel/logs/supportauth';

sub _ensure_log_directory {

    # make sure the log directory exists
    my $ticket_log_path_exists = -d $gl_ticket_log_path;
    if ( !$ticket_log_path_exists ) {
        Cpanel::SafeDir::MK::safemkdir($gl_ticket_log_path);
    }
    return;
}

sub _find_required_bins {
    my %bins = (
        'grep'     => scalar Cpanel::Binaries::path('grep'),
        'ifconfig' => scalar Cpanel::Binaries::path('ifconfig'),
        'netstat'  => scalar Cpanel::Binaries::path('netstat')
    );
    return \%bins;
}

sub _check_bound_ip {
    my ( $p_bins, $p_ip_to_check ) = @_;

    # check that the passed IP is bound to the server or configured in a supported NAT configuration #
    # we don't check all the configured IPs, or local IPs from NAT, because we want to know the IP #
    # is currently bound! this is a "will this work right now check", not will it work on next reboot #
    # or whatever #

    # make sure we have bins #
    Carp::croak '[PARAMETER] check_bound_ip requires bins for ifconfig and grep'
      if !defined $p_bins || !$p_bins->{'ifconfig'} || !$p_bins->{'grep'};

    # sanity check the incoming request #
    Carp::croak '[ARGUMENT] ip_to_check is required or not in the correct format'
      if !$p_ip_to_check || $p_ip_to_check !~ m/^[a-f0-9\.\[\]:]+$/i;

    # SIMPLE sanity check IP is bound to the server #
    # NOTE: $p_ip_to_check variable was checked for sanity earlier, there are #
    #   characters that need shell escaping at this point #

    if ( Cpanel::NAT::is_nat() ) {
        require Cpanel::IP::Configured;

        # support 1->1 NAT; note we check strictly against the NAT API to prevent a situation where configured, non-NAT IPs are unbound #
        foreach my $ip ( Cpanel::IP::Configured::getconfiguredips() ) {
            return 1 if Cpanel::NAT::get_public_ip($ip) eq $p_ip_to_check;
        }
        return 0;
    }

    require Cpanel::IP::LocalCheck;

    #we're not using NAT, so make sure we're bound in ipconfig.
    return Cpanel::IP::LocalCheck::ip_is_on_local_server($p_ip_to_check);
}

sub _check_bound_port {
    my ( $p_bins, $p_service, $p_port ) = @_;

    # check that the passed port is currently bound to a running service #
    # just like the _check_bound_ip method, this is a "will this work right now check", not #
    # will it work on next reboot or whatever #

    # make sure we have bins #
    Carp::croak '[PARAMETER] check_bound_ip requires bins for netstat and grep'
      if !defined $p_bins || !$p_bins->{'netstat'} || !$p_bins->{'grep'};

    # sanity check the incoming request #
    Carp::croak '[ARGUMENT] service is required or not in the correct format'
      if !$p_service || $p_service !~ m/^[a-z-]+$/i;
    Carp::croak '[ARGUMENT] port is required or not in the correct format'
      if !$p_port || $p_port !~ m/^\d+$/;

    # SIMPLE sanity check port is being listened to by service #
    # NOTE: $p_port and $p_service variables are checked for sanity earlier, there are #
    #   no characters that need shell escaping at this point #
    my $port_bound = !( system(qq{$p_bins->{'netstat'} -anp | $p_bins->{'grep'} -qP ':\\Q$p_port\\E\\b.+?LISTEN\\s+\\d+/\\Q$p_service\\E\\b'}) >> 8 );
    return $port_bound;
}

=head1 API

=head2 ticket_create_stub_ticket

Create a stub ticket. Additional API calls will be called to update this
ticket.

Note: In order to use this function, you must first have set up an OAuth
token in your current session. See Cpanel::OAuth2.

=head3 Parameters

n/a

=head3 Returns

B<On success, a structure containing the following values is returned:>

  ticket_id - number - ticket id that can be used to lookup or make additional changes to the ticket.

=cut

sub ticket_create_stub_ticket {
    my ( $args, $metadata ) = @_;

    require Whostmgr::TicketSupport;
    my $response = Whostmgr::TicketSupport::create_stub_ticket();

    if ($response) {
        if ( $response->{data} && $response->{data}{ticket_id} ) {
            $metadata->{result} = 1;
            $metadata->{reason} = 'OK';
            return $response->{data};
        }
        elsif ( $response->{error} ) {
            $metadata->{result} = 0;
            $metadata->{reason} = $response->{error};
            return;
        }
    }

    $metadata->{result} = 0;
    $metadata->{reason} = lh()->maketext('An unknown error occurred.');
    return;
}

=head2 ticket_get_support_agreement

Retrieves the Technical Support Agreement text along with some metadata
about the status of the agreement for this user.

Note: In order to use this function, you must first have set up an OAuth
token in your current session. See Cpanel::OAuth2.

=head3 Parameters

n/a

=head3 Returns

B<On success, a structure containing the following values is returned:>

         'accepted_date': (From the ticket system) The time in seconds since the epoch at which
                           the user associated with the OAuth token accepted the agreemnt.

   'accepted_date_human': (Computed by WHM) A human-readable version of accepted_date.

              'accepted': (From the ticket system) Whether the user associated with the OAuth
                          token has already accepted this version of the agreement.

                  'body': (Fetched by WHM from the URL provided by the ticket system) The full
                          support agreement text. This may contain HTML.

           'create_date': (Fetched by WHM from the URL provided by the ticket system) The time
                          in seconds since the epoch at which the support agreement was created/published.

     'create_date_human': (Computed by WHM) A human-readable version of create_date.

          'download_url': (Fetched by WHM from the URL provided by the ticket system) A URL at
                          which the end-user may download the support agreement.

                 'title': (Fetched by WHM from the URL provided by the ticket system) The
                          support agreement title.

               'version': (Fetched by WHM from the URL provided by the ticket system) The
                          version string of the support agreement document. The format of this string may
                          be unpredictable.

              'view_url': (Fetched by WHM from the URL provided by the ticket system) A URL at
                          which the end-user may view the support agreement as a standalone HTML document.

=cut

sub ticket_get_support_agreement {
    my ( $args, $metadata ) = @_;

    require Whostmgr::TicketSupport;
    my $agreement_info = Whostmgr::TicketSupport::get_support_agreement();

    if ($agreement_info) {
        if ( $agreement_info->{body} ) {
            $metadata->{result} = 1;
            $metadata->{reason} = 'OK';
            return $agreement_info;
        }
        elsif ( $agreement_info->{error} ) {
            $metadata->{result} = 0;
            $metadata->{reason} = $agreement_info->{error};
            return;
        }
    }

    $metadata->{result} = 0;
    $metadata->{reason} = lh()->maketext('An unknown error occurred.');
    return;
}

sub ticket_get_support_info {
    my ( $args, $metadata ) = @_;

    require Whostmgr::TicketSupport;
    my $support_info = Whostmgr::TicketSupport::get_support_info();
    if ($support_info) {
        if ( $support_info->{error} ) {
            $metadata->{result} = 0;
            $metadata->{reason} = $support_info->{error};
            return;
        }
        elsif ( $support_info->{data} ) {
            $metadata->{result} = 1;
            $metadata->{reason} = 'OK';
            return $support_info;
        }
    }

    $metadata->{result} = 0;
    $metadata->{reason} = lh()->maketext('An unknown error occurred.');
    return;
}

=head2 ticket_grant

=head3 Parameters

     'ticket_id': The ticket id for which you want to grant access.
    'server_num': The server number within that ticket for which you want to grant access. This is required to be
                  the one that corresponds to the server you're currently using.
  'ssh_username': (Optional) The username for incoming ssh connections (before escalating to root). If not
                  specified, the user from the ticket info is used.

=head3 Returns

B<On success, a structure containing the following items is returned:>

          'ssh_username': The username to use for ssh access to the server.
           'auth_status': This will always be 'AUTHED' on success, and is returned only for the benefit of the UI.
             'auth_time': Timestamp in epoch format for when access was granted.
         'ticket_status': This will always be 'OPEN' on success, and is returned only for the benefit of the UI.
             'ticket_id': The ticket id being granted.
            'server_num': The server number being granted.
           'server_name': The human-readable descriptive text for the server (if any) entered in the ticket system by the customer. For example: "My Server"
            'non_fatals': An array of strings indicating any non-fatal errors that occurred. It is normal for this to be empty.
          'chain_status': Whitelist status for iptables (see below)
        'hulk_wl_status': Whitelist status for cPHulk (see below)
         'csf_wl_status': Whitelist status for CSF (see below)
 'host_access_wl_status': Whitelist status for /etc/hosts.allow (see below)

B<For whitelist status items, possible values are:>

       'ACTIVE': The whitelist was successfully set up.
    'ERR_SETUP': An error occurred while trying to set up the whitelist.
  'ERR_UNKNOWN': An unknown error occurred.

B<On complete failure, no data is returned, but the usual metadata responses are set to indicate an error.>

=cut

sub ticket_grant {    ## no critic(Subroutines::ProhibitExcessComplexity)  -- Refactoring this function is a project, not a bug fix
    my ( $args, $metadata ) = @_;

    require Cpanel;
    require Cpanel::SSH;
    require Whostmgr::TicketSupport;
    require Whostmgr::TicketSupport::Server;
    require Whostmgr::TicketSupport::DataStore;

    # sanity check the inputs #

    my @args_missing;
    foreach my $arg (qw{ ticket_id server_num}) {
        push @args_missing, $arg
          if !$args->{$arg};
    }

    if ( scalar @args_missing ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = lh()->maketext( 'Missing [quant,_1,argument,arguments]: [join,~, ,_2]', scalar @args_missing, \@args_missing );
        return;
    }

    # tally up non-fatal errors so the UI can do something if needbe #
    my @non_fatals;

    # we'll resolve the user later, after the API call #
    my $provided_ssh_user;
    $provided_ssh_user = Cpanel::StringFunc::Trim::ws_trim( $args->{'ssh_username'} )
      if defined $args->{'ssh_username'};

    my $ticket_id = Cpanel::StringFunc::Trim::ws_trim( $args->{'ticket_id'} );
    if ( $ticket_id !~ m/^0*(\w{3,64})$/ ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = lh()->maketext( '“ticket_id” must be between 3 - 64 non-whitespace characters: [_1]', $ticket_id );
        return;
    }
    $ticket_id = $1;

    my $secure_id;
    if ( defined $args->{'secure_id'} ) {
        $secure_id = Cpanel::StringFunc::Trim::ws_trim( $args->{'secure_id'} );
        if ( $secure_id !~ m/^0*(\w{3,64})$/ ) {
            $metadata->{'result'} = 0;
            $metadata->{'reason'} = lh()->maketext( '“secure_id” must be between 3 - 64 non-whitespace characters: [_1]', $secure_id );
            return;
        }
        $secure_id = $1;
    }

    my $server_num = Cpanel::StringFunc::Trim::ws_trim( $args->{'server_num'} );
    if ( $server_num !~ m/^0*(\w{1,64})$/ ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = lh()->maketext( '“server_num” must be between 1 - 64 non-whitespace characters: [_1]', $server_num );
        return;
    }
    $server_num = $1;

    my ( $best_ssh_user, $wheel_password, $root_escalation_method ) = _determine_best_ssh_user( $ticket_id, $server_num, $metadata );
    return if !$best_ssh_user;

    # call out to the ticket system to get data for ticket/server #
    my ( $ticket_info, $ticket_info_status ) = Whostmgr::TicketSupport::get_authorization_information( $ticket_id, $server_num, $secure_id, ssh_user => $best_ssh_user, wheel_password => $wheel_password, root_escalation_method => $root_escalation_method );
    $ticket_info->{'ssh_username'} = $best_ssh_user if 'root' eq $ticket_info->{'ssh_username'};
    if ( !defined $ticket_info ) {
        $metadata->{'result'} = 0;
        if ( !defined $ticket_info_status ) {
            $metadata->{'reason'} = lh()->maketext(
                'The server is unable to contact the [asis,cPanel] Customer Portal to transmit the [asis,SSH] key. Manually import the key from the [asis,cPanel] Customer Portal. For more information on how to manually import [asis,SSH] keys into [asis,cPanel amp() WHM], see [output,url,_1,How to Authenticate Your Server,target,_2].',
                'https://go.cpanel.net/AuthenticateYourServer', '_new'
            );
        }
        elsif ( 401 == $ticket_info_status ) {
            $metadata->{'reason'} = lh()->maketext('The session with the [asis,cPanel] Customer Portal timed out. Refresh your browser and log in to the [asis,cPanel] Customer Portal.');
        }
        elsif ( 404 == $ticket_info_status ) {
            $metadata->{'reason'} = lh()->maketext( 'Ticket ID “[_1]” does not have any authorization information for Server “[_2]”. Access the [output,url,_3,cPanel Customer Portal,target,_4] to fill out the server authentication information.', $ticket_id, $server_num, Whostmgr::TicketSupport::Server::make_tickets_url('/'), '_new' );
        }
        else {
            $metadata->{'reason'} = lh()->maketext(
                'The server is unable to contact the [asis,cPanel] Customer Portal to transmit the [asis,SSH] key. Manually import the key from the [asis,cPanel] Customer Portal. For more information on how to manually import [asis,SSH] keys into [asis,cPanel amp() WHM], see [output,url,_1,How to Authenticate Your Server,target,_2].', 'https://go.cpanel.net/AuthenticateYourServer',
                '_new'
            );
        }

        return;
    }

    # override with argument? #
    $ticket_info->{'ssh_username'} = $provided_ssh_user
      if defined $provided_ssh_user && 'root' eq $ticket_info->{'ssh_username'};

    goto ticket_grant_skip_checks
      if !Cpanel::Binary::is_binary() && -e '/var/cpanel/MAXGOBUTTON_SKIP_CHECKS';

    # required binaries for operation #
    my $bins = _find_required_bins();
    foreach my $bin ( keys %{$bins} ) {
        if ( !-x $bins->{$bin} ) {
            $metadata->{'result'} = 0;
            $metadata->{'reason'} = lh()->maketext( q{A required program, [_1], is either not executable or does not exist.}, $bin );
            return;
        }
    }

    # SIMPLE sanity check IP/port for whm/ssh #
    foreach my $ip ( [ 'SSHd', $ticket_info->{'ssh_ip'} ], [ 'WHM', $ticket_info->{'whm_ip'} ] ) {
        next if !defined $ip->[1];
        if ( !_check_bound_ip( $bins, $ip->[1] ) ) {

            # ip is not bound on the server #
            $metadata->{'result'} = 0;
            $metadata->{'reason'} = lh()->maketext(
                '“[_1]” is not bound to “[_2]” for Ticket ID “[_3]” and Server “[_4]”. Access the [output,url,_5,cPanel Customer Portal,target,_6] and update the authentication information or select the correct Ticket ID and Server.',
                $ip->[1],
                $ip->[0],
                $ticket_id,
                $server_num,
                Whostmgr::TicketSupport::Server::make_tickets_url('/'),
                '_new'
            );
            return;
        }
    }
    if ( defined $ticket_info->{'ssh_port'} && !_check_bound_port( $bins, 'sshd', $ticket_info->{'ssh_port'} ) ) {

        # port is not active via SSH on the system #
        $metadata->{'result'} = 0;
        $metadata->{'reason'} =
          lh()->maketext( '[asis,SSHd] is not listening on port “[_1]” for ticket ID “[_2]” and server “[_3]”. Access the [output,url,_4,cPanel Customer Portal,target,_5] and update the authentication information or select the correct ticket ID and server.', $ticket_info->{'ssh_port'}, $ticket_id, $server_num, Whostmgr::TicketSupport::Server::make_tickets_url('/'), '_new' );
        return;
    }

    # sanity check the user #
    if ( !Cpanel::Validate::Username::is_valid( $ticket_info->{'ssh_username'} ) ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = lh()->maketext( 'The user, [_1], is not valid. All usernames must conform to Linux naming conventions. Access the [output,url,_2,cPanel Customer Portal,target,_3] and update the username.', $ticket_info->{'ssh_username'}, Whostmgr::TicketSupport::Server::make_tickets_url('/'), '_new' );
        return;
    }

    require Cpanel::Sys::User;

    # sanity check the user #
    my $sysuser = Cpanel::Sys::User->new( 'login' => $ticket_info->{'ssh_username'} );
    if ( !$sysuser->exists() ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = lh()->maketext(
            'The user, [_1], for Ticket ID “[_2]” and Server “[_3]” does not exist on the server. Verify that you have clicked Grant on the correct Ticket ID and Server. Access the [output,url,_4,cPanel Customer Portal,target,_5] to update the username.', $ticket_info->{'ssh_username'}, $ticket_id, $server_num, Whostmgr::TicketSupport::Server::make_tickets_url('/'),
            '_new'
        );
        return;
    }
    elsif ( $ticket_info->{'ssh_username'} ne 'root' && $ticket_info->{'root_escalation_method'} eq 'su' ) {
        require Cpanel::Sys::Escalate;
        if ( Cpanel::Sys::Escalate::is_su_broken() ) {
            $metadata->{'result'} = 0;
            $metadata->{'reason'} = lh()->maketext('The required setuid bit is not set for required program, [asis,su]. Set the correct permissions on the program, [asis,su].');
            return;
        }
        if ( !Cpanel::Sys::Escalate::can_user_su_to_root( $ticket_info->{'ssh_username'} ) ) {
            $metadata->{'result'} = 0;
            $metadata->{'reason'} = lh()->maketext( 'The User “[_1]” who you specified in Ticket ID “[_2]” and Server “[_3]” does not have access to use [asis,su] to escalate to the [asis,root] user. Verify that the user is a member of the “[_4]” group.', $ticket_info->{'ssh_username'}, $ticket_id, $server_num, 'wheel' );
            return;
        }
    }
    elsif ( $ticket_info->{'ssh_username'} ne 'root' && $ticket_info->{'root_escalation_method'} eq 'sudo' ) {
        require Cpanel::Sys::Escalate;
        if ( Cpanel::Sys::Escalate::is_sudo_broken() ) {
            $metadata->{'result'} = 0;
            $metadata->{'reason'} = lh()->maketext('The required setuid bit is not set for required program, [asis,sudo]. Set the correct permissions on the program, [asis,sudo].');
            return;
        }
        if ( !Cpanel::Sys::Escalate::can_user_sudo_to_root( $ticket_info->{'ssh_username'} ) ) {
            $metadata->{'result'} = 0;
            $metadata->{'reason'} = lh()->maketext( 'The User “[_1]” who you specified in Ticket ID “[_2]” and Server “[_3]” does not have access to use [asis,sudo] to escalate to the [asis,root] user. Verify that the user is a member of the “[_4]” group. You must install [asis,sudo] on the server.', $ticket_info->{'ssh_username'}, $ticket_id, $server_num, Cpanel::OS::sudoers() );
            return;
        }
    }
    elsif ( $ticket_info->{'ssh_username'} ne 'root' ) {

        # user is not root and we don't recognize the escalation method specified #
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = lh()->maketext( 'Ticket ID “[_1]” and Server “[_2]” specify an unsupported [asis,root] escalation method, [_3], for user “[_4]”.', $ticket_id, $server_num, $ticket_info->{'root_escalation_method'}, $ticket_info->{'ssh_username'} );
        return;
    }

  ticket_grant_skip_checks:

    # make sure it's not already authorized #
    my ( $keys, $warnings ) = Cpanel::SSH::_listkeys( 'user' => $ticket_info->{'ssh_username'}, 'private' => 0, 'public' => 1 );
    foreach my $key ( @{$keys} ) {
        next if defined $key->{'comment'} && $key->{'comment'} !~ m/^(\w{3,64})_server_(\w{1,64})\@cpanel.net_/;
        if ( $1 == $ticket_id && $2 == $server_num ) {
            $metadata->{'result'} = 0;
            $metadata->{'reason'} = lh()->maketext( 'The server detected that an SSH key for user “[_1]” in Ticket ID “[_2]” and Server “[_3]” already exists. Run the following [asis,cPanel] script and refresh your browser: [output,class,/scripts/updatesupportauthorizations,monospaced]', $ticket_info->{'ssh_username'}, $ticket_id, $server_num );
            return undef;
        }
    }

    # dissect the key info from the ticket system #
    if ( $ticket_info->{'ssh_key'} !~ m/^(ssh-\w+) ([A-Z0-9\/+=]+)/i ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = lh()->maketext( q{The [asis,cPanel] Customer Portal did not return a recognized key for Ticket ID “[_1]” and Server “[_2]”: [_3]}, $ticket_id, $server_num, $ticket_info->{'ssh_key'} );
        return undef;
    }
    my $local_time = time();
    my $comment    = "${ticket_id}_server_${server_num}\@cpanel.net_$local_time";

    # we'll need the timestamp on the file #
    my $user_homedir = Cpanel::SSH::_getsshdir( $ticket_info->{'ssh_username'} );
    if ( !$user_homedir ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = lh()->maketext( 'The system could not create the required files in the [output,class,.ssh/,monospaced] directory for “[_1]”. Verify that the correct owner and permissions exist for the user’s home directory.', $ticket_info->{'ssh_username'} );
        return undef;
    }

    # generate key hash #
    my %key = (
        'ssh_username' => $ticket_info->{'ssh_username'},
        'ssh_text'     => "$1 $2 $comment"
    );

    # import the key #
    $key{'ssh_file'} = Cpanel::SSH::_importkey( 'user' => $ticket_info->{'ssh_username'}, 'name' => $comment, 'key' => $key{'ssh_text'} );
    if ( !$key{'ssh_file'} ) {
        my $key_members = join( ', ', map { qq{$_="} . ( defined $key{$_} ? $key{$_} : 'undef' ) . q{"} } keys %key );
        Cpanel::Debug::log_warn("Failed to call Cpanel::SSH::_importkey: $key_members; $Cpanel::CPERROR{'ssh'}");
        $metadata->{'result'} = 0;
        $metadata->{'reason'} =
          lh()->maketext( 'An internal failure on the server prevented the authorization of the [asis,SSH] key. Manually import the key from the [asis,cPanel] Customer Portal. For more information on how to manually import [asis,SSH] keys into [asis,cPanel amp() WHM], see [output,url,_1,How to Authenticate Your Server,target,_2].', 'https://go.cpanel.net/AuthenticateYourServer', '_new' );
        return undef;
    }

    # now authorize it #
    if ( !Cpanel::SSH::_authkey( 'user' => $ticket_info->{'ssh_username'}, 'authorize' => 1, 'file' => $key{'ssh_file'} ) ) {
        Cpanel::Debug::log_warn("Failed to call Cpanel::SSH::_authkey: ssh_username=$ticket_info->{'ssh_username'}, authorize=1, file=$key{'ssh_file'}; $Cpanel::CPERROR{'ssh'}");
        $metadata->{'result'} = 0;
        $metadata->{'reason'} =
          lh()->maketext( 'An internal failure on the server prevented the authorization of the [asis,SSH] key. Manually import the key from the [asis,cPanel] Customer Portal. For more information on how to manually import [asis,SSH] keys into [asis,cPanel amp() WHM], see [output,url,_1,How to Authenticate Your Server,target,_2].', 'https://go.cpanel.net/AuthenticateYourServer', '_new' );
        return undef;
    }

    my @stats = stat("${user_homedir}/$key{'ssh_file'}");
    $key{'mtime'} = $stats[9];

    # write the current state of affairs #
    my $ds           = Whostmgr::TicketSupport::DataStore->new();
    my @stored_users = @{ $ds->get('users') || [] };
    push @stored_users, $key{'ssh_username'}
      if !grep { $_ eq $key{'ssh_username'} } @stored_users;
    $ds->set( 'users', \@stored_users )->cleanup();
    $ds = undef;

    # log to the audit log #
    _ensure_log_directory();
    my $auditlog = Cpanel::SafeFile::safeopen( \*AUDITLOG, '>>', $gl_ticket_log );
    if ( !$auditlog ) {
        Cpanel::Debug::log_warn("Could not write to $gl_ticket_log: $!");
        push @non_fatals, 'AUDIT_LOG';
    }
    else {
        chmod 0600, $gl_ticket_log;
        my $now         = localtime( time() );
        my $remote_user = $ENV{'REMOTE_USER'} || 'undef';
        my $remote_addr = $ENV{'REMOTE_ADDR'} || 'undef';
        print AUDITLOG "$now:GRANT:$remote_user:$ENV{'USER'}:$remote_addr:$key{'ssh_file'}\n";
        Cpanel::SafeFile::safeclose( \*AUDITLOG, $auditlog );
    }

    my $access_ips = Whostmgr::TicketSupport::access_ips() || die("Could not retrieve access IPs!");
    my @whitelist_status;
    for my $whitelist_type (qw(IpTables cPHulk CSF HostAccess)) {
        my $wl_class = "Whostmgr::TicketSupport::$whitelist_type";
        Cpanel::LoadModule::load_perl_module($wl_class);
        my $wl_obj = $wl_class->new( ssh_port => $ticket_info->{'ssh_port'}, access_ips => $access_ips );
        if ( $wl_obj->should_skip() ) {
            $wl_obj->finish();
            next;
        }
        eval {
            if ( !$wl_obj->active() ) {
                push @whitelist_status, $wl_obj->STATUS_NAME => ( $wl_obj->setup() ? 'ACTIVE' : 'ERR_SETUP' );
            }
            else {
                push @whitelist_status, $wl_obj->STATUS_NAME => 'ACTIVE';
            }
        };
        if ($@) {
            Cpanel::Debug::log_warn($@);
            push @whitelist_status, $wl_obj->STATUS_NAME => 'ERR_UNKNOWN';
        }
        $wl_obj->finish();
    }

    # let the ticket system know what happened #
    if ( !Whostmgr::TicketSupport::log_entry( $ticket_id, $server_num, 'ssh_key_grant' ) ) {
        push @non_fatals, 'TICKET_SYSTEM_LOG_ENTRY';
    }

    # imported and authorized successfully #
    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';

    return { 'ssh_username' => $key{'ssh_username'}, 'auth_status' => 'AUTHED', 'auth_time' => $key{'mtime'}, 'ticket_status' => 'OPEN', 'ticket_id' => $ticket_id, 'server_num' => $server_num, 'server_name' => $ticket_info->{'server_name'}, 'non_fatals' => \@non_fatals, @whitelist_status };
}

# Arguments:
# - $ticket_id - The ticket id we're dealing with
# - $server_num - The server number we're dealing with
# - $metadata - API metadata where error information will be stored, if applicable
#
# Returns:
# On success,
#   - The user to use for ssh logins
#   - The wheel user password, if applicable (undef otherwise)
#   - The root escalation method (may be either 'sudo' or empty string to signify that privilege escalation is not needed)
# On failure,
#   - Nothing
#
# Side effects:
# - On error, $metadata will be populated with 'result' and 'reason' fields
sub _determine_best_ssh_user {
    my ( $ticket_id, $server_num, $metadata ) = @_;

    require Whostmgr::Services::SSH::Config;

    # If sshd does not permit root logins, try to find an alternative
    my $permit_root_setting = Whostmgr::Services::SSH::Config->new()->get_config('PermitRootLogin');
    if ( defined $permit_root_setting && $permit_root_setting =~ m/no|forced-commands-only/i ) {
        require Cpanel::Sys::Escalate;

        # If root login would not have worked, but sudo is available, create a temporary
        # wheel user for use with this ticket.
        if ( Cpanel::Sys::Escalate::is_sudo_available() ) {
            require Whostmgr::TicketSupport::TempWheelUser;
            my ( $wheel_user, $wheel_password ) = Whostmgr::TicketSupport::TempWheelUser::get($ticket_id);
            return $wheel_user, $wheel_password, 'sudo';
        }
        else {
            require Whostmgr::TicketSupport::Server;
            $metadata->{'result'} = 0;
            $metadata->{'reason'} = lh()->maketext(
                'The [asis,SSHd] configuration on the server for Ticket ID “[_1]” and Server “[_2]” disables [asis,root] logins. The system has [asis,sudo] disabled. Enable [asis,root] logins or enable [asis,sudo] for wheel users. Access the [output,url,_3,cPanel Customer Portal,target,_4] to update the authorization information.',
                $ticket_id,
                $server_num,
                Whostmgr::TicketSupport::Server::make_tickets_url('/'), '_new'
            );
            return;
        }
    }

    return 'root', undef, '';
}

sub _ticket_revoke_inner {
    my ( $p_ssh_username, $p_matchers, $ticket_id ) = @_;

    # tally up non-fatal errors so the UI can do something if needbe #
    my @non_fatals;

    # ensure sanity #
    Carp::croak '[ARGUMENT] matchers must include at least one qualifier.'
      if !@{$p_matchers};
    Carp::croak '[ARGUMENT] ticket_id must be provided.'
      if !defined $ticket_id;
    Carp::croak '[ARGUMENT] ticket_id must be a number.'
      unless $ticket_id =~ m{^[0-9]*$};

    # prepare to write to the audit log #
    _ensure_log_directory();
    my $auditlog = Cpanel::SafeFile::safeopen( \*AUDITLOG, '>>', $gl_ticket_log );
    my ( $now, $remote_user, $remote_addr );
    if ( !$auditlog ) {
        Cpanel::Debug::log_warn("Could not write to $gl_ticket_log: $!");
        push @non_fatals, 'AUDIT_LOG';
    }
    else {
        # no sense doing some of this if the audit log isn't able to be opened for writing #
        chmod 0600, $gl_ticket_log;
        $now         = localtime( time() );
        $remote_user = $ENV{'REMOTE_USER'} || 'undef';
        $remote_addr = $ENV{'REMOTE_ADDR'} || 'undef';
    }

    require Cpanel;
    require Cpanel::SSH;
    require Whostmgr::TicketSupport;

    # if any keys match the input args, delete them #
    my ( $keys, $warnings ) = Cpanel::SSH::_listkeys( 'user' => $p_ssh_username, 'private' => 0, 'public' => 1 );
    my $revoked_keys = 0;
    my @problem_keys;

    foreach my $key ( @{$keys} ) {

        # check against all matchers #
        next if @{$p_matchers} != grep { $key->{'text'} =~ $_ } @{$p_matchers};

        # make sure we recognize the data from the key comment #
        next if $key->{'comment'} !~ m/^(\w{3,64})_server_(\w{1,64})\@cpanel.net_/;
        my $ticket_id  = $1;
        my $server_num = $2;

        # delete if it's a match #
        if ( !defined $key->{'file'} ) {

            # delete by key text if no file #
            if ( Cpanel::SSH::_authkey( 'user' => $p_ssh_username, 'text' => $key->{'text'}, 'authorize' => 0 ) ) {
                Cpanel::Debug::log_warn("Failed to call Cpanel::SSH::_authkey: ssh_username=$p_ssh_username, text=$key->{'text'}; $Cpanel::CPERROR{'ssh'}");
                push @problem_keys, "COMMENT: $key->{'comment'}";
                next;
            }
        }
        elsif ( !Cpanel::SSH::_delkey( 'user' => $p_ssh_username, 'file' => $key->{'file'} ) ) {
            Cpanel::Debug::log_warn("Failed to call Cpanel::SSH::_delkey: ssh_username=$p_ssh_username, file=$key->{'file'}; $Cpanel::CPERROR{'ssh'}");
            push @problem_keys, $key->{'file'};
            next;
        }
        $revoked_keys++;

        # write to the audit log #
        print AUDITLOG "$now:REVOKE:$remote_user:$ENV{'USER'}:$remote_addr:$key->{'file'}\n"
          if $auditlog;

        # Log each revoked ticket so there is a complete audit trail
        my $resp = eval { Whostmgr::TicketSupport::log_entry( $ticket_id, $server_num, 'ssh_key_revoke' ); };

        my $exception = $@;
        if ( ( !$resp || $exception ) && !grep( $_ eq 'TICKET_SYSTEM_LOG_ENTRY', @non_fatals ) ) {

            # Only report the log failure once in the list of non-fatal errors.
            push @non_fatals, 'TICKET_SYSTEM_LOG_ENTRY';
        }
    }

    require Whostmgr::TicketSupport::TempWheelUser;
    if ( Whostmgr::TicketSupport::TempWheelUser::exists($ticket_id) ) {
        Whostmgr::TicketSupport::TempWheelUser::cleanup($ticket_id);
    }

    # clean up the log #
    if ($auditlog) {
        Cpanel::SafeFile::safeclose( \*AUDITLOG, $auditlog );
    }

    return $revoked_keys, \@problem_keys, \@non_fatals;
}

sub _remove_whitelists_if_necessary {

    require Whostmgr::TicketSupport;

    # handle removal of whitelist items, if necessary #
    my $access_ips = Whostmgr::TicketSupport::access_ips() || die("Could not retrieve access IPs!");
    my @whitelist_status;
    for my $whitelist_type (qw(IpTables cPHulk CSF HostAccess)) {
        my $wl_class = "Whostmgr::TicketSupport::$whitelist_type";
        Cpanel::LoadModule::load_perl_module($wl_class);
        my $wl_obj = $wl_class->new( access_ips => $access_ips );
        if ( $wl_obj->should_skip() ) {
            $wl_obj->finish();
            next;
        }
        eval {
            my $wl_active = $wl_obj->active();
            if ( $wl_active && !$wl_obj->still_needed ) {
                push @whitelist_status, $wl_obj->STATUS_NAME => ( $wl_obj->unsetup ? 'INACTIVE' : 'ERR_UNSETUP' );
            }
            else {
                push @whitelist_status, $wl_obj->STATUS_NAME => ( $wl_active ? 'ACTIVE' : 'INACTIVE' );
            }
        };
        if ($@) {
            Cpanel::Debug::log_warn($@);
            push @whitelist_status, $wl_obj->STATUS_NAME => 'ERR_UNKNOWN';
        }
        $wl_obj->finish();
    }
    return @whitelist_status;
}

=head2 ticket_revoke

=head3 Description

Revoke access to this server for the specified ticket.

=head3 Parameters

  'ssh_username': The username for ssh logins.
     'ticket_id': The ticket id for which access to this server is being revoked.
    'server_num': (Optional) The server number for which access to this server is being revoked. (Must always be the server number from the
                  ticket that corresponds to this server, even though others are litsed.)

=head3 Returns

           'revoked_keys': A numeric counter indicating how many total keys were revoked.
             'non_fatals': An array of non-fatal errors that occurred, if any. It is normal for this to be empty.
           'chain_status': Whitelist status for iptables (see whitelist status section)
          hulk_wl_status': Whitelist status for cPHulk (see whitelist status section)
          'csf_wl_status': Whitelist status for CSF (see whitelist status section)
  'host_access_wl_status': Whitelist status for /etc/hosts.allow (see whitelist status section)

B<For whitelist status items, possible values are:>

       'INACTIVE': The whitelist was successfully removed.
    'ERR_UNSETUP': An error occurred while trying to set up the whitelist.
    'ERR_UNKNOWN': An unknown error occurred.

B<On complete failure, no data is returned, but the usual metadata responses are set.>

=cut

sub ticket_revoke {
    my ( $args, $metadata ) = @_;

    # sanity check the inputs #

    my @args_missing;
    foreach my $arg (qw{ ssh_username ticket_id }) {
        push @args_missing, $arg
          if !$args->{$arg};
    }

    if ( scalar @args_missing ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = lh()->maketext( 'Missing [quant,_1,argument,arguments]: [join,~, ,_2]', scalar @args_missing, \@args_missing );
        return;
    }

    my ( $ssh_username, $terms, $matchers ) = _internal_build_search_matchers( $args, $metadata );
    return undef if !defined $matchers;

    my @non_fatals;

    # call inner logic that's shared with other functions #
    my ( $revoked_keys, $problem_keys, $inner_non_fatals ) = _ticket_revoke_inner( $ssh_username, $matchers, $args->{'ticket_id'} );
    push @non_fatals, @{$inner_non_fatals};

    if ( @{$problem_keys} ) {

        # sticky situation you see, we technically did work (maybe) but we still failed #
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = lh()->maketext( 'An internal error occurred while attempting to revoke one or more keys: [join,~, ,_1]', $problem_keys );
        return { 'revoked_keys' => $revoked_keys, 'non_fatals' => \@non_fatals };
    }

    if ( !$revoked_keys ) {

        # no work was done, let the caller know #
        my $tmp_server_num = $terms->{'server_num'} || 'undef';
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = lh()->maketext( 'The server could not find any keys for the specified ticket and server: [asis,ssh_username=][_1], [asis,ticket_id=][_2], [asis,server_num=][_3]', $ssh_username, $terms->{'ticket_id'}, $tmp_server_num );
        return undef;
    }

    my @whitelist_status = _remove_whitelists_if_necessary();

    # authorization revoked successfully #
    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';
    return {
        'revoked_keys' => $revoked_keys, 'ticket_id' => $terms->{'ticket_id'}, 'server_num' => $terms->{'server_num'}, 'ssh_username' => $ssh_username, 'non_fatals' => \@non_fatals,
        @whitelist_status
    };    # TODO: This returns unneeded data, and it should be made consistent with the abridged return value from the partial failure scenario (and the documentation). This change may need its own story, though, in order to prevent the scope of the documentation story from growing too large. These return values are expected to be unnecessary: ticket_id, server_num, ssh_username.
}

=head2 ticket_update_service_agreement_approval

=head3 Description

Informs the ticket system that the user has approved the support
service agreement, and it can update the approval timestamp in its
records.

=head3 Parameters

  'version': A string representing the version of the agreement to which the customer agreed.

=head3 Returns

This function returns only metadata.

=cut

sub ticket_update_service_agreement_approval {
    my ( $args, $metadata ) = @_;

    if ( !$args->{version} ) {
        die lh()->maketext('The [asis,version] parameter is required.') . "\n";
    }

    require Whostmgr::TicketSupport;
    my ( $response, $status ) = Whostmgr::TicketSupport::update_agreement_approval( version => $args->{version} );

    if ( $status == 200 ) {
        $metadata->{'result'} = 1;
        $metadata->{'reason'} = 'OK';
    }
    else {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = lh()->maketext( 'The ticket system failed to update the Technical Support Agreement approval information, and returned a [output,acronym,HTTP,Hypertext Transfer Protocol] “[_1]” status code: [_2]', $status, $response->{'message'} );
    }
    return undef;
}

=head2 ticket_remove_closed

=head3 Description

Revoke access for and remove any tickets from the list that are already closed in the ticket system.

=head3 Parameters

None

=head3 Returns

           'revoked_keys': The total number of keys that were revoked.
           'chain_status': iptables whitelist status (see whitelist status section)
         'hulk_wl_status': cPHulk whitelist status (see whitelist status section)
          'csf_wl_status': CSF whitelist status (see whitelist status section)
  'host_access_wl_status': Whitelist status for /etc/hosts.allow (see whitelist status section)
             'non_fatals': An array of non-fatal errors (if any) that occurred. It is normal for this to be empty.

B<For whitelist status items, possible values are:>

       'INACTIVE': The whitelist was successfully removed.
    'ERR_UNSETUP': An error occurred while trying to set up the whitelist.
    'ERR_UNKNOWN': An unknown error occurred.

B<On complete failure, no data is returned, but the usual metadata responses are set.>

=cut

sub ticket_remove_closed {
    my ( $args, $metadata ) = @_;

    my @non_fatals;

    # enumerate the list and find un-opened tickets that have expired server authorizations #
    # and call inner logic that's shared with other functions #
    my $list = _authorizations_list();
    my ( $all_revoked_keys, @all_problem_keys );
    foreach my $ticket_id ( keys %$list ) {
        my $ticket = $list->{$ticket_id};
        next if $ticket->{'ticket_status'} eq 'OPEN';
        foreach my $server ( values %{ $ticket->{'servers'} } ) {
            next if $server->{'auth_status'} ne 'EXPIRED';

            my $returned_metadata = {};
            my ( undef, undef, $matchers ) = _internal_build_search_matchers( { 'ticket_id' => $ticket_id }, $returned_metadata );
            if ( !$matchers ) {
                $metadata = $returned_metadata;
                return;
            }
            my ( $revoked_keys, $problem_keys, $inner_non_fatals ) = _ticket_revoke_inner( $server->{'ssh_username'}, $matchers, $ticket_id );
            $all_revoked_keys += $revoked_keys;
            push @all_problem_keys, @{$problem_keys};
            push @non_fatals,       @{$inner_non_fatals};
        }
    }
    if (@all_problem_keys) {

        # sticky situation you see, we technically did work (maybe) but we still failed #
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = lh()->maketext( 'An internal error occurred while attempting to revoke one or more keys: [join,~, ,_1]', \@all_problem_keys );
        return { 'revoked_keys' => $all_revoked_keys, 'non_fatals' => \@non_fatals };
    }

    if ( !$all_revoked_keys ) {

        # no work was done, let the caller know #
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = lh()->maketext('There were no server authorizations found from closed tickets on your server.');
        return undef;
    }

    my @whitelist_status = _remove_whitelists_if_necessary();

    # closed tickets with authorizations revoked successfully #
    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';
    return { 'revoked_keys' => $all_revoked_keys, @whitelist_status, 'non_fatals' => \@non_fatals };
}

sub _authorizations_list {
    my ( $p_user, $p_matchers ) = @_;

    # open the data store for reading and updating #
    require Whostmgr::TicketSupport::DataStore;
    my $ds = Whostmgr::TicketSupport::DataStore->new();

    require Whostmgr::TicketSupport;

    # get local authorizations #
    my $local = Whostmgr::TicketSupport::local_authorizations_list( $p_user, $p_matchers, $ds );

    # get remote authorizations #
    my ( $remote, $remote_status ) = Whostmgr::TicketSupport::remote_authorizations_list( $p_user, $p_matchers );
    if ( !defined $remote || $remote_status != 200 ) {

        # we need to make the local list still sane for the reply here #
        foreach my $ticket_id ( keys %{$local} ) {
            my $ticket = $local->{$ticket_id} || {};
            $ticket->{'ticket_id'} = $ticket_id;

            # fixup fields for UI #
            $ticket->{'ticket_status'} = 'UNKNOWN';
            my $ticket_list = $ds->get('tickets');
            $ticket->{'ticket_subject'} = defined $ticket_list ? ( $ticket_list->{$ticket_id}->{'ticket_subject'} || 'UNKNOWN' ) : 'UNKNOWN';

            foreach my $server_num ( keys %{ $local->{$ticket_id}->{'servers'} } ) {
                my $server = $ticket->{'servers'}->{$server_num};
                $server->{'server_num'} = $server_num;

                # make sure the UI knows what's up #
                $server->{'auth_status'} = 'AUTHED';
            }
        }

        # release datastore #
        $ds->abort();

        return $local;
    }

    my ( %tickets, %users );

    # first remote authorizations that are currently authorized locally #
    foreach my $ticket_id ( keys %{$remote} ) {

        # setup initial structure #
        my $remote_ticket = $remote->{$ticket_id};
        $tickets{$ticket_id} = {
            'ticket_id'      => $ticket_id,
            'ticket_subject' => $remote_ticket->{'ticket_subject'},
            'ticket_status'  => 'OPEN',
            'servers'        => {}
        };

        # find the authorization if it was done locally #
        foreach my $server_num ( keys %{ $remote_ticket->{'servers'} } ) {

            # fixup and make sure we have a server structure to work with #
            my $server = $remote_ticket->{'servers'}->{$server_num};
            $server->{'server_num'} = $server_num;

            # we need a computed server_key, instead of num, because we treat the 3 pieces of data we have as a key #
            my $server_key = "${ticket_id}_${server_num}_$server->{'ssh_username'}";

            # handle states, authed or not, and associate with the final ticket return structure #
            if ( defined $local->{$ticket_id}->{'servers'}->{$server_num} && $server->{'ssh_username'} eq $local->{$ticket_id}->{'servers'}->{$server_num}->{'ssh_username'} ) {

                # ticket is still open #
                $tickets{$ticket_id}->{'servers'}->{$server_key} = {

                    # incorporate local data #
                    %{ $local->{$ticket_id}->{'servers'}->{$server_num} },

                    # with remote data #
                    %{$server},

                    # and the overall status #
                    'auth_status' => 'AUTHED'
                };

                # cache that we saw this user #
                $users{ $server->{'ssh_username'} } = 1;
            }
            else {
                # ticket is open but not authorized #
                $tickets{$ticket_id}->{'servers'}->{$server_key} = {

                    # only local data and status are needed #
                    %{$server},
                    'auth_status' => 'NOT_AUTHED'
                };
            }
        }
    }

    # second cross ref the local auths with already accounted for auths, these are closed ticket auths #
    my $old_tickets = $ds->get('tickets');
    foreach my $ticket_id ( keys %{$local} ) {
        $tickets{$ticket_id}->{'ticket_id'} ||= $ticket_id;

        # if there's no subject, it's because the remote open-tickets call didn't list it because it's now closed #
        $tickets{$ticket_id}->{'ticket_status'} ||= 'CLOSED';

        # copy in any remaining keys that are not defined yet... #
        $tickets{$ticket_id}->{$_} = $old_tickets->{$ticket_id}->{$_} for grep { $_ ne 'servers' && !defined $tickets{$ticket_id}->{$_} } keys %{ $old_tickets->{$ticket_id} };

        foreach my $server_num ( keys %{ $local->{$ticket_id}->{'servers'} } ) {

            # fixup and make sure we have a server structure to work with #
            my $server = $tickets{$ticket_id}->{'servers'}->{$server_num} || $local->{$ticket_id}->{'servers'}->{$server_num};
            $server->{'server_num'} ||= $server_num;

            # we need a computed server_key, instead of num, because we treat the 3 pieces of data we have as a key #
            my $server_key = "${ticket_id}_${server_num}_$server->{'ssh_username'}";

            # authorizations are tracked by ticket_id, server_num and user, so if the user changes and the ticket is still open, make sure the status is right #
            if ( !( defined $tickets{$ticket_id}->{'servers'}->{$server_key} && $server->{'ssh_username'} eq $local->{$ticket_id}->{'servers'}->{$server_num}->{'ssh_username'} ) ) {
                $tickets{$ticket_id}->{'servers'}->{$server_key} = $server;

                # make sure we capture the expired status #
                $server->{'auth_status'} = 'EXPIRED';
            }

            # cache that we saw this user #
            $users{ $server->{'ssh_username'} } = 1;
        }
    }

    # only affect cache if we're not filtered #
    if ( defined $ds ) {
        if ( !defined $p_user && ( !$p_matchers || !@{$p_matchers} ) ) {

            # Freshly store/replace the ticket and user list, but leave other data (if any) unaltered.
            $ds->set( 'tickets', \%tickets );
            $ds->set( 'users',   [ keys %users ] );
        }
        $ds->cleanup();
        $ds = undef;
    }

    # return the whole thing #
    return \%tickets;
}

sub _authorizations_list_simplified {
    my @args  = @_;
    my $auths = _authorizations_list(@args);

    # needed for ip bound check #
    my $bins = _find_required_bins();
    foreach my $bin ( keys %{$bins} ) {
        if ( !-x $bins->{$bin} ) {
            die lh()->maketext( q{A required program, [_1], is either not executable or does not exist.}, $bin );
        }
    }

    my @tickets;
    foreach my $ticket_id ( sort { $b <=> $a } keys %{$auths} ) {

        # rip the servers out, we'll be turning them into an array and checking the IP #
        my $servers_hash = delete $auths->{$ticket_id}->{'servers'} || {};
        my @servers_array;
        foreach my $server_num ( sort { $servers_hash->{$a}->{'server_num'} <=> $servers_hash->{$b}->{'server_num'} } keys %{$servers_hash} ) {

            my $server = $servers_hash->{$server_num};

            # check that the IP is bound, if it is, we can visually mark it in the UI #
            if ( $server->{'ssh_ip'} && $server->{'ssh_port'} ) {
                $server->{'bound'} = _check_bound_ip( $bins, $server->{'ssh_ip'} ) ? 1 : 0;
            }

            # add to the server array #
            push @servers_array, $server;
        }

        # and push the re-constituted, final result #
        push @tickets, { %{ $auths->{$ticket_id} }, 'servers' => \@servers_array };
    }

    # return the whole, new thing! #
    return \@tickets;
}

=head2 ticket_list

=head3 Description

Returns the list of tickets associated with the Manage2 account and the authorization status
for each.

=head3 Parameters

     'ticket_id': (Optional) Constrain the results to those matching the specified ticket id.
    'server_num': (Optional) Constrain the results to those matching the specified server number.
  'ssh_username': (Optional) Constrain the results to those for which the SSH username is the specified user.

The normal usage is to call ticket_list with no parameters specified.

=head3 Returns

'auths': An array containing data structures representing each ticket associated with the
Manage2 account being used, containing:

  'ticket_status': The status of the ticket. (See COMMON STATUS STRINGS at end)
        'servers': An array of hashes describing the servers associated with the ticket. (See below)
 'ticket_subject': The subject of the ticket.
      'ticket_id': The numeric id of the ticket in the ticket system.

The structure of each element in the 'servers' array is:

    'ssh_username': The username to use for connecting to the server.
      'server_num': The server number as stored in the ticket system.
     'auth_status': The status of the ticket (See COMMON STATUS STRINGS at end of document).
             'ssh': The IP address / port to use for connecting to the server over ssh (as listed
                    in the ticket).
       'auth_time': Timestamp in epoch format of when the ticket in qustion was granted for this server.
           'bound': Boolean value indicating whether the IP address for the server as listed in the
                    ticket system is currently bound locally. (In other words, whether this server is
                    likely to be relevant or just another server listed in the ticket.)
          'whm_ip': The IP address to use for connecting to WHM (as listed in the ticket).
     'server_name': The human-readable name for the server (if any) entered in the ticket system.

Example:

  {"auths":
      [
          {"ticket_status":"UNKNOWN","servers":
              [
                  {"ssh_username":"root","server_num":"2","auth_status":"AUTHED","ssh":"10.11.12.13:22",
                   "auth_time":1400000000,"bound":1,"whm_ip":"10.11.12.13","server_name":"My Server"}
              ],
              "ticket_subject":"Example ticket","ticket_id":"9999999999999"}
      ]
  }

=cut

sub ticket_list {
    my ( $args, $metadata ) = @_;

    my ( $user, undef, $matchers ) = _internal_build_search_matchers( $args, $metadata );
    return undef if !defined $matchers;

    # an undef matchers list means went bad, but we still want it undef when it's empty #
    $matchers = undef if !@{$matchers};

    # get the list of authorized keys #
    my $tickets = _authorizations_list_simplified( $user, $matchers );

    # NOTE: sort? #

    # give the list back! #
    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';
    return { 'auths' => $tickets };
}

=head2 ticket_whitelist_check

=head3 Description

Check whether the current state of the firewall whitelist is
consistent with the state of ticket grants.

If at least one ticket is granted, the whitelist should be active.
If no tickets are granted, the whitelist should not be active.

Note that this currently does not check the cPHulk whitelist,
only iptables and CSF.

=head3 Parameters

None

=head3 Returns

A structure containing:

'chain_status': A string indicating the overall whitelist status:

    'ACTIVE': The whitelist is active.
  'INACTIVE': The whitelist is not active.

'problem': A string indicating whether there is a problem with the current status:

           'NO': There is not a problem. No action is needed.
   'NEED_SETUP': The whitelist needs to be set up (i.e., there is at least one ticket
                 granted but the whitelist is not currently active).
  NEED_UNSETUP': The whitelist needs to be removed (i.e., the whitelist is currently
                 active, but no tickets are granted).

=cut

sub ticket_whitelist_check {
    my ( $args, $metadata ) = @_;

    my %data = ( 'chain_status' => 'UNKNOWN', 'problem' => 'NO' );

    my $wl_obj       = _firewall_wl_obj();
    my $chain_active = $wl_obj->active;

    $data{'chain_status'} = $chain_active ? 'ACTIVE' : 'INACTIVE';

    if ( !$chain_active && $wl_obj->still_needed ) {
        $data{'problem'} = 'NEED_SETUP';
    }
    elsif ( $chain_active && !$wl_obj->still_needed ) {
        $data{'problem'} = 'NEED_UNSETUP';
    }

    $wl_obj->finish();

    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';
    return \%data;
}

=head2 ticket_whitelist_setup

=head3 Description

Set up the necessary firewall whitelist entries to allow cPanel support staff access to the server.
This is only meant to be called in response to a problem reported by ticket_whitelist_check, as
the normal grant and revoke process already handles the setup/unsetup of whitelist entries.

This function is firewall-specific and does not cover cPHulk.

=head3 Parameters

None

=head3 Returns

'chain_status': A string indicating whether the operation succeeded or failed.

     'ACTIVE': The whitelist was successfully set up.
  'ERR_SETUP': An error occurred. (See /usr/local/cpanel/logs/error_log for more information.)

=cut

sub ticket_whitelist_setup {
    my ( $args, $metadata ) = @_;

    my %data;

    my $wl_obj = _firewall_wl_obj();
    $wl_obj->setup;
    $data{'chain_status'} = $wl_obj->active ? 'ACTIVE' : 'ERR_SETUP';

    $wl_obj->finish();

    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';
    return \%data;
}

=head2 ticket_whitelist_unsetup

=head3 Description

Remove firewall whitelist entries. This is only meant to be called in response to a problem
reported by ticket_whitelist_check, as the normal grant and revoke process already handles the
setup/unsetup of whitelist entries.

This function is firewall-specific and does not cover cPHulk.

=head3 Parameters

None

=head3 Returns

'chain_status': A string indicating whether the operation succeeded or failed.

     'INACTIVE': The whitelist was successfully removed.
  'ERR_UNSETUP': An error occurred. (See /usr/local/cpanel/logs/error_log for more information.)

=cut

sub ticket_whitelist_unsetup {
    my ( $args, $metadata ) = @_;

    my %data;

    my $wl_obj = _firewall_wl_obj();
    $wl_obj->unsetup;
    $data{'chain_status'} = !$wl_obj->active ? 'INACTIVE' : 'ERR_UNSETUP';

    $wl_obj->finish();

    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';
    return \%data;
}

sub _firewall_wl_obj {
    for my $class (qw(Whostmgr::TicketSupport::IpTables Whostmgr::TicketSupport::CSF)) {
        Cpanel::LoadModule::load_perl_module($class);
        my $obj = $class->new();
        if ( !$obj->should_skip() ) {
            return $obj;
        }
        $obj->finish();
    }
    die "Could not determine the correct firewall software to use";    # This line should be unreachable and indicates a bug
}

sub _internal_build_search_matchers {

    # prepare an array of compiled regexs that will be used to match on #
    # also sanity checks the terms #
    my ( $args, $metadata ) = @_;

    my $ssh_username;
    my %terms;
    my @matchers;

    if ( $args->{'ssh_username'} ) {
        $ssh_username = Cpanel::StringFunc::Trim::ws_trim( $args->{'ssh_username'} );
        if ( !Cpanel::Validate::Username::is_valid($ssh_username) ) {
            $metadata->{'result'} = 0;
            $metadata->{'reason'} = lh()->maketext( 'The following User is not valid: [_1]', $ssh_username );
            return;
        }
    }

    if ( $args->{'ticket_id'} ) {
        my $ticket_id = Cpanel::StringFunc::Trim::ws_trim( $args->{'ticket_id'} );
        if ( $ticket_id !~ m/^0*(\w{3,64})$/ ) {
            $metadata->{'result'} = 0;
            $metadata->{'reason'} = lh()->maketext( '“ticket_id” must be between 3 - 64 non-whitespace characters: [_1]', $ticket_id );
            return;
        }
        $ticket_id = $1;
        $terms{'ticket_id'} = $ticket_id;
        push @matchers, qr/\s+\Q$ticket_id\E_server_\w{1,64}\@cpanel.net_\d+$/;
    }

    if ( $args->{'server_num'} ) {
        my $server_num = Cpanel::StringFunc::Trim::ws_trim( $args->{'server_num'} );
        $server_num =~ s/^0+//;
        if ( $server_num !~ m/^0*(\w{1,64})$/ ) {
            $metadata->{'result'} = 0;
            $metadata->{'reason'} = lh()->maketext( '“server_num” must be between 1 - 64 non-whitespace characters: [_1]', $server_num );
            return;
        }
        $server_num = $1;
        $terms{'server_num'} = $server_num;
        push @matchers, qr/\s+\w{3,64}_server_\Q$server_num\E\@cpanel.net_\d+$/;
    }

    # note it's OK that we have no matchers, the list backend will handle that #
    return $ssh_username, \%terms, \@matchers;
}

sub _ssh_test_validate_args {
    my ( $args, $metadata ) = @_;

    # sanity check the inputs #

    my @args_missing;
    foreach my $arg (qw{ ticket_id server_num }) {
        push @args_missing, $arg
          if !$args->{$arg};
    }

    if ( scalar @args_missing ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = lh()->maketext( 'Missing [quant,_1,argument,arguments]: [join,~, ,_2]', scalar @args_missing, \@args_missing );
        return;
    }

    my $ticket_id = Cpanel::StringFunc::Trim::ws_trim( $args->{'ticket_id'} );
    if ( $ticket_id !~ m/^0*(\w{3,64})$/ ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = lh()->maketext( '“ticket_id” must be between 3 - 64 non-whitespace characters: [_1]', $ticket_id );
        return;
    }
    $ticket_id = $1;

    my $server_num = Cpanel::StringFunc::Trim::ws_trim( $args->{'server_num'} );
    if ( $server_num !~ m/^0*(\w{1,64})$/ ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = lh()->maketext( '“server_num” must be between 1 - 64 non-whitespace characters: [_1]', $server_num );
        return;
    }
    $server_num = $1;

    return ( $ticket_id, $server_num );
}

sub _ssh_test_start {
    my ( $metadata, $ticket_id, $server_num ) = @_;

    require Whostmgr::TicketSupport;

    # call out to the ticket system and authorize the key #
    my ( $test_id, $start_status, $start_message ) = Whostmgr::TicketSupport::connection_test_start( $ticket_id, $server_num );
    if ( 200 != $start_status ) {
        require Whostmgr::TicketSupport::Server;
        if ($start_message) {
            Cpanel::Debug::log_warn("Failed to start the connection test due to an HTTP $start_status error: $start_message");
        }
        else {
            Cpanel::Debug::log_warn("Failed to start the connection test due to an HTTP $start_status error!");
        }
        $metadata->{'result'} = 0;
        $metadata->{'reason'} =
          lh()->maketext( 'Due to an [output,acronym,HTTP,Hypertext Transfer Protocol] “[_1]” error, the server is unable to contact the [asis,cPanel] Customer Portal to start the [asis,SSH] test. Verify that the server’s firewall allows IP addresses for “[output,class,_2,monospaced]” to connect.', $start_status, Whostmgr::TicketSupport::Server::tickets_hostname() );
        return;
    }

    return $test_id;
}

=head2 ticket_ssh_test_start

Initiates an SSH connection test for a particular server tied to a ticket and does not wait for the result.

=head3 Parameters

   'ticket_id': The ticket ID for which the SSH test should be performed.
  'server_num': The server number from that ticket for which the SSH test should be performed. (Must correspond to this server.)

=head3 Returns

n/a

=cut

sub ticket_ssh_test_start {
    my ( $args, $metadata ) = @_;

    # Validate args
    my ( $ticket_id, $server_num ) = _ssh_test_validate_args( $args, $metadata );
    return if !defined $ticket_id || !defined $server_num;

    require Cpanel::ForkAsync;
    my $pid = Cpanel::ForkAsync::do_in_child(
        sub {
            require Cpanel::CloseFDs;
            require Cpanel::Logger;

            # API processor children have a pipe open to whostmgrd, and this needs to be
            # closed in order for this grandchild to be independent of whostmgrd. Otherwise,
            # whostmgrd will end up waiting on this grandchild to finish with the pipe.
            Cpanel::CloseFDs::fast_daemonclosefds();

            # The fast_daemonclosefds call messes up the Cpanel::Logger instance, and if
            # you try to reinstantiate it, it wants to pull from singleton storage. This
            # call prevents that from happening.
            Cpanel::Logger::clear_singleton_stash();

            open( STDERR, '>>', '/usr/local/cpanel/logs/error_log' ) || die "Could not redirect STDERR to /usr/local/cpanel/logs/error_log: $!";
            open( STDOUT, '>>', '/usr/local/cpanel/logs/error_log' ) || die "Could not redirect STDOUT to /usr/local/cpanel/logs/error_log: $!";

            # Start the SSH test
            my ($test_id) = _ssh_test_start( $metadata, $ticket_id, $server_num );
            if ( !$test_id ) {
                Cpanel::Debug::log_info( $metadata->{reason} );
            }
        }
    );

    # Success
    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';

    # This special metadata field is only for testing purposes and does not need to be documented.
    # Callers should not rely on this field because it may go away in the future.
    $metadata->{'_pid'} = $pid;

    return {};
}

=head2 ticket_ssh_test

=head3 Parameters

   'ticket_id': The ticket id for which the ssh test should be performed.
  'server_num': The server number from that ticket for which the ssh test should be performed. (Must be this server.)

=head3 Returns

      'result': The status of the ssh test, as reported by the ticket system API.
  'non_fatals': An array of strings indicating any non-fatal errors that occurred. It is normal for this to be empty.

=cut

sub ticket_ssh_test {
    my ( $args, $metadata ) = @_;

    # Validate args
    my ( $ticket_id, $server_num ) = _ssh_test_validate_args( $args, $metadata );
    return if !defined $ticket_id || !defined $server_num;

    # Start the SSH test
    my ($test_id) = _ssh_test_start( $metadata, $ticket_id, $server_num );
    return if !defined $test_id;

    my ( $result, $result_status, $result_message );
    my @non_fatals;

    require Whostmgr::TicketSupport;
    require Whostmgr::TicketSupport::Server;

    # now enter poll loop #
    my $wait  = 1;
    my $start = time();
    while ( time() - $start < 150 ) {

        # wait for a short time ... #
        sleep $wait;

        # see if we have success, or failure as it could be #
        ( $result, $result_status, $result_message ) = Whostmgr::TicketSupport::connection_test_result($test_id);
        if ( $result_status != 200 && $result_status != 202 ) {
            if ($result_message) {
                Cpanel::Debug::log_warn("Failed to get results of ssh-test due to an HTTP $result_status error: $result_message");
            }
            else {
                Cpanel::Debug::log_warn("Failed to get results of ssh-test due to an HTTP $result_status error!");
            }
            $metadata->{'result'} = 0;
            $metadata->{'reason'} =
              lh()->maketext( 'Due to an [output,acronym,HTTP,Hypertext Transfer Protocol] “[_1]” error, the server is unable to contact the [asis,cPanel] Customer Portal to start the [asis,SSH] test. Verify that the server’s firewall allows IP addresses for “[output,class,_2,monospaced]” to connect.', $result_status, Whostmgr::TicketSupport::Server::tickets_hostname() );
            return;
        }

        # are we done? #
        last if 200 == $result_status;

        # taking a while, we'll do it fast style to start #
        $wait = 3
          if 1 == $wait && time() - $start > 5;
    }

    # log to the audit log #
    _ensure_log_directory();
    my $auditlog = Cpanel::SafeFile::safeopen( \*AUDITLOG, '>>', $gl_ticket_log );
    if ( !$auditlog ) {
        my $reason = $! || 'safeopen call had an internal failure';
        Cpanel::Debug::log_warn(qq{Could not write to "$gl_ticket_log": $reason});
        push @non_fatals, 'AUDIT_LOG';
    }
    else {
        chmod 0600, $gl_ticket_log;
        my $now         = localtime( time() );
        my $remote_user = $ENV{'REMOTE_USER'} || 'undef';
        my $remote_addr = $ENV{'REMOTE_ADDR'} || 'undef';
        print AUDITLOG "$now:SSH_TEST:$remote_user:$ENV{'USER'}:$remote_addr:Test for '$ticket_id' server $server_num was '$result'\n";
        Cpanel::SafeFile::safeclose( \*AUDITLOG, $auditlog );
    }

    # If the ticket system still hasn't changed its status to report
    # either success or failure, then we need to report that we gave
    # up waiting on the ticket system.
    if ( $result eq '__TESTING__' ) {
        $result = 'TICKET_SYSTEM_TIMEOUT';
    }

    # We got a result back from the ticket system, report it
    # along with any non-fatal local problems encountered.
    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';
    return { 'result' => $result, 'non_fatals' => \@non_fatals };
}

=head2 ticket_validate_oauth2_code

=head3 Description

Validates an OAuth2 code returned from the ticket system and attempts to
retrieve the actual token that can be used for API calls. If it's retrieved,
the token is stored on the current session.

=head3 Parameters

          'code': The code received from the OAuth2 redirect. It will be
                  validated and exchanged for a token.
  'redirect_uri': The same redirect_uri query argument that was passed to the
                  initial OAuth2 authentication endpoint.

=head3 Returns

This method does not return any data, but the API result will be 1 if the
OAuth2 code was valid and an OAuth2 token was successfully stored on the
session.

=cut

sub ticket_validate_oauth2_code {
    my ( $args, $metadata ) = @_;

    require Whostmgr::TicketSupport::Token;
    eval { Whostmgr::TicketSupport::Token->new()->fetch($args); };

    if ($@) {
        $metadata->{result} = 0;
        $metadata->{reason} = $@->isa("Cpanel::Exception") ? $@->to_locale_string_no_id() : $@;
    }
    else {
        $metadata->{result} = 1;
        $metadata->{reason} = 'OK';
    }

    return;
}

1;

__END__

=head1 COMMON STATUS STRINGS

=head2 non_fatals (array of zero or more strings)

'AUDIT_LOG': Couldn't record the grant operation in our local audit log.

'TICKET_SYSTEM_LOG_ENTRY': Couldn't record the grant operation in the ticket through the ticket system API.

=head2 ticket_status (string)

'OPEN': The ticket is open in the ticket system.

'CLOSED': The ticket is closed in the ticket system.

'UNKNOWN': The ticket status couldn't be determined.

=head2 auth_status (string)

'AUTHED': Access for the ticket and server in question has been granted.

'NOT_AUTHED': Access has not been granted.

'EXPIRED': Access was granted but has expired.

=head2 whitelist status (chain_status, hulk_wl_status, csf_wl_status, host_access_wl_status)

'ACTIVE': The appropriate whitelist entries were either added or were already in place.

'INACTIVE': The whitelist entries were successfully removed or were already gone.

'ERR_SETUP': Failed to add the whitelist entries.

'ERR_UNSETUP': Failed to remove the whitelist entries.

'ERR_UNKNOWN': An unknown error occurred.
