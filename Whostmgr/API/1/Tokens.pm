package Whostmgr::API::1::Tokens;

# cpanel - Whostmgr/API/1/Tokens.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=head1 NAME

Whostmgr::API::1::Tokens - API calls that allow a user to manage their API tokens

=head1 SYNOPSIS

    use Whostmgr::API::1::Tokens;

    my $metadata = {};
    my $created_token = Whostmgr::API::1::Tokens::api_token_create({ 'token_name' => 'my_token' }, $metadata);
    print "Created token: $created_token->{'token'}\n";

=head1 DESCRIPTION

This module encapsulates the public-facing API calls used in the S<"Manage API Tokens"> interface in WHM.

These API calls are available for 3rdparty developers as part of the WHM API v1 layer.

=cut

use Try::Tiny;
use Cpanel::Imports;

use Whostmgr::ACLS                                      ();
use Cpanel::Server::Type                                ();
use Cpanel::SafeFile                                    ();
use Cpanel::Exception                                   ();
use Cpanel::ConfigFiles                                 ();
use Whostmgr::ACLS::Data                                ();
use Whostmgr::API::1::Utils                             ();
use Cpanel::Security::Authn::APITokens::whostmgr        ();
use Cpanel::Security::Authn::APITokens::Write::whostmgr ();

use constant NEEDS_ROLE => {
    api_token_create      => undef,
    api_token_list        => undef,
    api_token_revoke      => undef,
    api_token_update      => undef,
    api_token_get_details => undef,
};

=head1 METHODS

=head2 api_token_create($args_hr, $metadata_hr)

Creates a new API token for the user.

=over 3

=item C<< \%args_hr >> [in, required]

A hashref with the following keys:

=over 3

=item C<< token_name => $name >> [in, required]

The name to associate with the generated token.

This name must be B<unique> - if a token by the same name exists, then an
error is returned.

=item C<< expires_at => $unixtime >> [in, optional]

The time in unix seconds at which the token should expire.

=item C<< whitelist_ip => $ips_or_range >> [in, optional]

A list of IP addresses or CIDR ip address ranges. These IP addresses are whitelisted.
When defined, only request from the specific IP addresses or address ranges are valid.
All other request with this token are rejected.

Multiple IPs or CIDR IP address ranges can be defined using:

    whitelist_ip="232.22.22.1"
    whitelist_ip="232.22.22.4"
    whitelist_ip="232.22.22.7"
    whitelist_ip="232.55.0.0/24"

You can intermix IP addresses and IP address ranges in any combination.

=item C<< acl => $acl_name >> [in, optional]

ACLs to assign to the token.

Multiple ACLs can be specified by adding "-N" to the name. For example:

    acl-1="list-accts"
    acl-2="suspend-acct"
    acl-3="kill-acct"

Will assign "list-accts, suspend-acct, kill-acct" to the token.

B<NOTE>: If no ACLs are specified then the token will inherit all ACLs
currently assigned to the WHM user.

=back

=item C<< \%metadata_hr >> [in, required]

A hashref that will be populated with information about the API call.  The following keys will be populated:

=over 3

=item C<result> [out]

True iff the API call succeeded.

=item C<reason> [out]

The reason for failure.  If no failure occurred, contains 'OK'.

=back

=back

B<Returns>: On failure, returns an empty hashref.  On success, the following data is returned in a hashref:

=over 3

=item C<token>

The plaintext API token that was generated.

B<Note>: This is the only time we expose the plaintext token. The caller must save this data in order to use the token properly.

=item C<name>

The name of the API token as specified by the caller.

=item C<create_time>

The time the API token was created (unixepoch)

=item C<acls>

An array containing the set of ACLs assigned to the API token.

B<NOTE>: This is only returned if ACLs were assigned to the token.

=back

=cut

sub api_token_create {
    my ( $args, $metadata ) = @_;

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    my $token_details = {};
    try {
        my ( $token_name, $token_args_ar ) = _build_create_or_update_args($args);
        my $data_obj = Cpanel::Security::Authn::APITokens::Write::whostmgr->new( { 'user' => $ENV{'REMOTE_USER'} } );
        $token_details = $data_obj->create_token( @{$token_args_ar} );
        $data_obj->save_changes_to_disk();

        _update_accounting_log( "CREATEAPITOKEN", $token_name );
    }
    catch {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = locale->maketext( 'The system failed to create the [asis,API] token: [_1]', Cpanel::Exception::get_string_no_id($_) );
    };
    return {} if !$metadata->{'result'};

    return $token_details;
}

=head2 api_token_get_details

See OpenAPI.

=cut

sub api_token_get_details ( $args, $metadata, @ ) {
    my $token = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'token' );

    require Cpanel::Security::Authn::APITokens::whostmgr;
    my $tokens_obj = Cpanel::Security::Authn::APITokens::whostmgr->new( { user => $ENV{'REMOTE_USER'} } );

    $metadata->set_ok();

    my $out = $tokens_obj->look_up_by_token($token);
    $out &&= $out->export();

    return $out;
}

=head2 api_token_list(undef, $metadata_hr)

Lists the active API tokens for the user.

=over 3

=item C<< \%metadata_hr >> [in, required]

A hashref that will be populated with information about the API call.  The following keys will be populated:

=over 3

=item C<result> [out]

True iff the API call succeeded.

=item C<reason> [out]

The reason for failure.  If no failure occurred, contains 'OK'.

=back

=back

B<Returns>: On failure, returns an empty hashref.  On success, the following data is returned in a hashref:

=over 3

=item C<tokens>

An Array of Hashes, wherein each HashRef contains the following details for the active API tokens:

=over 3

=item C<name>

The name of the API token as specified by the caller.

=item C<create_time>

The time the API token was created (unixepoch)

=item C<acls>

A HashRef detailing the ACLs currently enforced on the API token.

=back

=back

=cut

sub api_token_list {
    my ( undef, $metadata ) = @_;

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    Whostmgr::ACLS::init_acls();

    my $tokens_hr = {};
    try {
        my $thirdparty_acls = _thirdparty_acls();

        my %user_acls = (
            %Whostmgr::ACLS::default,
            %{$thirdparty_acls},
            %{ $ENV{'REMOTE_USER'} eq 'root' ? { 'all' => 1 } : Whostmgr::ACLS::get_filtered_reseller_privs() },
        );

        my $data_obj = Cpanel::Security::Authn::APITokens::whostmgr->new( { 'user' => $ENV{'REMOTE_USER'} } );
        foreach my $token_obj ( values %{ $data_obj->read_tokens() } ) {
            my %user_acls_copy = %user_acls;

            if ( $token_obj->has_full_access() && $user_acls{'all'} ) {

                # filter_acls() doesn’t do this for us.
                $_ = 1 for values %user_acls_copy;
            }
            else {
                if ( !$user_acls{'all'} ) {

                    # A non-root token needs NOT to mention
                    # ACLs that the reseller doesn’t have.
                    delete @user_acls_copy{ grep { !$user_acls_copy{$_} } keys %user_acls_copy };
                }

                $token_obj->filter_acls( \%user_acls_copy );
            }

            $_ ||= 0 for values %user_acls_copy;

            my $token_data = $token_obj->export();
            $token_data->{'acls'} = \%user_acls_copy;

            $tokens_hr->{ $token_data->{'name'} } = $token_data;
        }
    }
    catch {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = locale->maketext( 'The system failed to read the [asis,API] tokens: [_1]', Cpanel::Exception::get_string_no_id($_) );
    };
    return {} if !$metadata->{'result'};

    return { 'tokens' => $tokens_hr };
}

=head2 api_token_update($args_hr, $metadata_hr)

Updates an existing API token for the user.

=over 3

=item C<< \%args_hr >> [in, required]

A hashref with the following keys:

=over 3

=item C<< token_name => $name >> [in, required]

The name of the token being updated.

=item C<< new_name => $new_name >> [in, optional]

The new name to assign to the token.

This name must be B<unique> - if a token by the same name exists, then an
error is returned.

=item C<< expires_at => $unixtime >> [in, optional]

The time in unix seconds at which the token should expire.

=item C<< acl => $acl_name >> [in, optional]

ACLs to assign to the token.

Multiple ACLs can be specified by adding "-N" to the name. For example:

    acl-1="list-accts"
    acl-2="suspend-acct"
    acl-3="kill-acct"

Will assign "list-accts, suspend-acct, kill-acct" to the token.

B<NOTE>: If no ACLs are specified then the token will inherit all ACLs
currently assigned to the WHM user.

=back

=item C<< \%metadata_hr >> [in, required]

A hashref that will be populated with information about the API call.  The following keys will be populated:

=over 3

=item C<result> [out]

True iff the API call succeeded.

=item C<reason> [out]

The reason for failure.  If no failure occurred, contains 'OK'.

=back

=back

B<Returns>: On failure, returns an empty hashref.  On success, the following data is returned in a hashref:

=over 3

=item C<name>

The name of the API token as specified by the caller.

=item C<old_name>

The previous name associated with the API token.

=item C<create_time>

The time the API token was created (unixepoch)

=item C<acls>

An array containing the set of ACLs assigned to the API token.

B<NOTE>: This is only returned if ACLs were assigned to the token.
If this is not set, then the API token inherits all ACLs currently assigned to the WHM user.

=back

=cut

sub api_token_update {
    my ( $args, $metadata ) = @_;

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    my $token_details = {};
    try {
        my ( $token_name, $token_args_ar ) = _build_create_or_update_args($args);
        my $data_obj = Cpanel::Security::Authn::APITokens::Write::whostmgr->new( { 'user' => $ENV{'REMOTE_USER'} } );
        $token_details = $data_obj->update_token( @{$token_args_ar} );
        $data_obj->save_changes_to_disk();

        _update_accounting_log( "UPDATEAPITOKEN", $token_name );
    }
    catch {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = locale->maketext( 'The system failed to update the [asis,API] token: [_1]', Cpanel::Exception::get_string_no_id($_) );
    };
    return {} if !$metadata->{'result'};

    return $token_details;
}

=head2 api_token_revoke($args_hr, $metadata_hr)

Revokes the specified API token for the user.

=over 3

=item C<< \%args_hr >> [in, required]

A hashref with the following keys:

=over 3

=item C<< token_name => $name >> [in, required]

The name of the API token to revoke. This is the name specified in the C<api_token_create> call.

=back

=item C<< \%metadata_hr >> [in, required]

A hashref that will be populated with information about the API call.  The following keys will be populated:

=over 3

=item C<result> [out]

True iff the API call succeeded.

=item C<reason> [out]

The reason for failure.  If no failure occurred, contains 'OK'.

=back

=back

B<Returns>: Returns an empty hashref.  The success/failure of the operation is relayed through the C<$metadata_hr>.

=cut

sub api_token_revoke {
    my ( $args, $metadata ) = @_;

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    try {
        my @token_names = ( map { $args->{$_} } grep { $_ =~ m/^token_name(?:-[0-9]+)?$/ } keys %{$args} );
        die Cpanel::Exception::create( 'MissingParameter', 'Provide at least one “[_1]” argument.', ['token_name'] )
          if !scalar @token_names;

        my $tokens_revoked = 0;
        my $data_obj       = Cpanel::Security::Authn::APITokens::Write::whostmgr->new( { 'user' => $ENV{'REMOTE_USER'} } );
        foreach my $token_name (@token_names) {
            if ( $data_obj->revoke_token($token_name) ) {
                $tokens_revoked++;
                _update_accounting_log( "REVOKEAPITOKEN", $token_name );
            }
        }
        $data_obj->save_changes_to_disk()
          if $tokens_revoked;
    }
    catch {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = locale->maketext( 'The system failed to revoke the [asis,API] token: [_1]', Cpanel::Exception::get_string_no_id($_) );
    };

    return {};
}

=head2 _update_accounting_log($action, $token_name)

Logs an account creation/deletion to the cPanel accounting log.

=over 3

=item C<< $action >> [in, required]

A string containing an uppercase keyword for the action being logged.

=item C<< $token_name >> [in, required]

The name of the API token.

=back

=cut

# mocked in tests
sub _update_accounting_log {
    my ( $action, $token_name ) = @_;

    my $acctlog = Cpanel::SafeFile::safeopen( my $accounting_log_fh, '>>', $Cpanel::ConfigFiles::ACCOUNTING_LOG_FILE );
    if ( !$acctlog ) {
        logger->warn("Could not write to /var/cpanel/accounting.log");
    }
    else {
        chmod 0600, $Cpanel::ConfigFiles::ACCOUNTING_LOG_FILE;

        # The accounting log format is:
        # <time>:<action keyword>:<remote user>:<user>:<domain>:<other items particular to the action>
        # We are using "not-applicable" for the domain since it isn't really necessary here.
        print $accounting_log_fh localtime() . ":$action:$ENV{'REMOTE_USER'}:$ENV{'REMOTE_USER'}:not-applicable:$token_name\n";
        Cpanel::SafeFile::safeclose( $accounting_log_fh, $acctlog );
    }
    return 1;
}

sub _parse_and_validate_acls {
    my $args = shift;

    my ( @acls, @invalid_acls );
    my $is_dnsonly      = Cpanel::Server::Type::is_dnsonly();
    my $cpanel_acls     = Whostmgr::ACLS::Data::ACLS();
    my $thirdparty_acls = _thirdparty_acls();

    foreach my $acl_specified ( map { $args->{$_} } grep { $_ =~ m/^acl(\-[0-9]+)?$/ } keys %{$args} ) {

        # Is the ACL valid?
        if ( exists $cpanel_acls->{$acl_specified} ) {
            if ( $is_dnsonly && !$cpanel_acls->{$acl_specified}->{'dnsonly'} ) {
                push @invalid_acls, $acl_specified;
                next;
            }
        }
        elsif ( !exists $thirdparty_acls->{$acl_specified} ) {
            push @invalid_acls, $acl_specified;
            next;
        }

        # Is the ACL authorized, i.e., does the user have the ACL?
        if ( $Whostmgr::ACLS::ACL{'all'} || $Whostmgr::ACLS::ACL{$acl_specified} ) {
            push @acls, $acl_specified;
            next;
        }
        push @invalid_acls, $acl_specified;
    }
    die Cpanel::Exception::create( 'InvalidParameter', 'Invalid or unauthorized [numerate,_1,ACL,ACLs] specified: [list_and,_2]', [ scalar @invalid_acls, \@invalid_acls ] )
      if scalar @invalid_acls;

    return \@acls;
}

sub _thirdparty_acls {
    return {
        map { $_->{acl} => $_->{default_value} }
        map { @{$_} } values( ( Whostmgr::ACLS::get_dynamic_acl_lists() )[0]->%* )
    };
}

sub _build_create_or_update_args {
    my ($args) = @_;

    # Cpanel::Security::Authn::APITokens::Validate will throw an exception if
    # the token name is missing so this wouldn't be necessary except that we
    # need to extract the name to update the accounting log.
    my $token_name = $args->{'token_name'} // die Cpanel::Exception::create( 'MissingParameter', 'The parameter “[_1]” is required.', ['token_name'] );

    # TODO: Move ACL validation to Cpanel::Security::Authn::APIToken::Validate
    my $acls_ar       = _parse_and_validate_acls($args);
    my @whitelist_ips = Whostmgr::API::1::Utils::get_length_arguments( $args, 'whitelist_ip' );

    # If the 'any' whitelist_ip argument is provided then it supercedes any
    # other possible IPs and will clear any existing IP list in the token.
    my $clear_ips;
    if ( grep { $_ eq 'any' } @whitelist_ips ) {
        $clear_ips     = 1;
        @whitelist_ips = ();
    }

    return (
        $token_name,
        [
            {
                ( 'name' => $token_name ),
                ( exists $args->{'new_name'}   ? ( 'new_name'      => $args->{'new_name'} )   : () ),
                ( scalar @{$acls_ar}           ? ( 'acls'          => $acls_ar )              : () ),
                ( exists $args->{'expires_at'} ? ( 'expires_at'    => $args->{'expires_at'} ) : () ),
                ( scalar @whitelist_ips        ? ( 'whitelist_ips' => \@whitelist_ips )       : () ),
                ( $clear_ips                   ? ( 'whitelist_ips' => undef )                 : () ),
            }
        ]
    );
}

1;
