package Whostmgr::API::1::Email;

# cpanel - Whostmgr/API/1/Email.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::Exception                  ();
use Cpanel::PwCache                    ();
use Whostmgr::Email                    ();
use Whostmgr::Authz                    ();
use Cpanel::Email::UserForward         ();
use Cpanel::Email::Setup::MobileConfig ();
use Whostmgr::API::1::Utils            ();

use constant NEEDS_ROLE => 'MailReceive';

=encoding utf-8

=head1 NAME

Whostmgr::API::1::Email

=head2 list_pops_for

=head3 Description

This function allows an administrative user or application to safely obtain information
about the email accounts belonging to a cPanel account.

In this case, "safely" means that the following precautions are taken:

  - Reading data from the user's home directory is only done as that user, not as root.

  - The data from the user's home directory is not trusted:

      - The list of domains from the user's home directory is not treated as authoritative
        because the user could have manipulated it. Instead, the list of domains we care
        about is obtained from the server-wide user domains list.

      - The list of local parts for a given domain is validated before being trusted.

=head3 Arguments

'user': String - (required) The cPanel account for which you wish to obtain a list of email accounts.

=head3 Returns

'pops': Array - This array contains the list of email accounts belonging to the user in question.

=cut

sub list_pops_for ( $args, $metadata, $api_args ) {
    my $username = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'user' );

    my $remote_sr = _proxy_this_api_call( $username, $args, $metadata, $api_args );
    return $$remote_sr if $remote_sr;

    my $pops = Whostmgr::Email::list_pops_for($username);

    @$metadata{qw(result reason)} = qw(1 OK);
    return { pops => $pops };
}

=head2 get_user_email_forward_destination

=head3 Description

This function allows an administrative user or application to set the
forwarding destination for a specific user.

The types of emails sent depend on the user being forwarded:

    - In general, the system sends emails about problems on the server and normal server activity to “root.”
    - If you do not use suexec, the “nobody” user receives bounce messages from email that CGI scripts send

=head3 Arguments

'user': String - (required) The cPanel account for which you wish to get the forwarding destination

=head3 Returns

'forward_to': Array - This array contains the list of forwarding destinations.

=cut

sub get_user_email_forward_destination ( $args, $metadata, $api_args ) {
    my $username = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'user' );

    if ( _looks_like_cpusername($username) ) {
        my $remote_sr = _proxy_this_api_call( $username, $args, $metadata, $api_args );
        return $$remote_sr if $remote_sr;
    }

    my $forward = Cpanel::Email::UserForward::get_user_email_forward_destination( 'user' => $username );

    @$metadata{qw(result reason)} = qw(1 OK);
    return { 'forward_to' => $forward };
}

=head2 set_user_email_forward_destination

=head3 Description

This function allows an administrative user or application to set the
forwarding destination for a specific user.

The types of emails sent depend on the user being forwarded:

    - In general, the system sends emails about problems on the server and normal server activity to “root.”
    - If you do not use suexec, the “nobody” user receives bounce messages from email that CGI scripts send

=head3 Arguments

'user': String - (required) The cPanel account for which you wish to set the new forward
'forward_to': String - (required) The cPanel account or email to which you wish to forward. Setting to “” disables the forward.

=cut

sub set_user_email_forward_destination ( $args, $metadata, $api_args ) {

    my $username = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'user' );

    if ( _looks_like_cpusername($username) ) {
        my $remote_sr = _proxy_this_api_call( $username, $args, $metadata, $api_args );
        return $$remote_sr if $remote_sr;
    }

    my $success = Cpanel::Email::UserForward::set_user_email_forward_destination( 'user' => $username, 'forward_to' => $args->{'forward_to'} );

    @$metadata{qw(result reason)} = ( $success, $success ? 'OK' : "NOT OK" );
    return {};
}

=head2 normalize_user_email_configuration

=head3 Description

This API will detect and fix various misconfigurations of a user’s email
configuration, including ownership and permissions of email-related files
and directories.

=head3 Arguments

=over

=item * C<username>

=back

=head3 Returns

None.

=cut

sub normalize_user_email_configuration ( $args, $metadata, $api_args ) {
    my $username = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'username' );
    my $homedir  = Cpanel::PwCache::gethomedir($username) or do {
        die Cpanel::Exception::create( 'UserNotFound', [ name => $username ] );
    };

    my $remote_sr = _proxy_this_api_call( $username, $args, $metadata, $api_args );
    return $$remote_sr if $remote_sr;

    require Cpanel::Email::Perms::User;
    Cpanel::Email::Perms::User::ensure_all_perms($homedir);

    $metadata->set_ok();

    return;
}

=head2 generate_mobileconfig

=head3 Description

This function generates a .mobileconfig file for an email account
or system user.

=head3 Arguments

'account'                   : String - (required) The cPanel account or Webmail account for which you wish to get generate the .mobileconfig file
'use_ssl'                   : Boolean - (required) Whether to connect over SSL transport or not
'selected_account_services' : String - (optional) comma delimited list of one or more of the following: carddav,caldav,email

=head3 Returns

'payload': Base64-encoded binary - a .mobileconfig file

=cut

sub generate_mobileconfig ( $args, $metadata, $api_args ) {

    my $account = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'account' );

    my $remote_sr = _proxy_this_api_call( $account, $args, $metadata, $api_args );
    return $$remote_sr if $remote_sr;

    # This code is here as a workaround for a bug in CPANEL-30509
    require Cpanel::AcctUtils::Lookup;
    my $system_user = eval { Cpanel::AcctUtils::Lookup::get_system_user($account); };
    if ($@) {
        $system_user = $account;
    }
    Whostmgr::Authz::verify_account_access($system_user);

    @$metadata{qw(result reason)} = ( 0, 'NOT OK' );

    my $payload = Cpanel::Email::Setup::MobileConfig::generate(
        'account'                   => $account,
        'use_ssl'                   => $args->{'use_ssl'},
        'selected_account_services' => $args->{'selected_account_services'} || ''
    );

    @$metadata{qw(result reason)} = ( 1, 'OK' );

    require MIME::Base64;

    return { 'payload' => MIME::Base64::encode_base64($payload) };
}

#----------------------------------------------------------------------

sub _proxy_this_api_call ( $acct_name, $args, @other_args ) {
    my $fn = ( caller 1 )[3] =~ s<.+::><>r;

    require Whostmgr::API::1::Utils::Proxy;
    my $remote = Whostmgr::API::1::Utils::Proxy::proxy_if_configured(
        function       => $fn,
        perl_arguments => [ $args, @other_args ],
        worker_type    => 'Mail',
        account_name   => $acct_name,
    );

    return $remote && \$remote->get_raw_data();
}

sub _looks_like_cpusername ($name) {
    return $name ne 'root' && $name ne 'nobody' && $name ne 'cpanel';
}

1;
