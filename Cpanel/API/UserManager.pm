
# cpanel - Cpanel/API/UserManager.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::API::UserManager;

use cPstrict;

use Carp              ();
use Cpanel::ApiUtils  ();
use Cpanel::Carp      ();
use Cpanel::Exception ();
use Cpanel::Locale::Lazy 'lh';
use Cpanel::Rand::Get                 ();
use Cpanel::UserManager               ();
use Cpanel::UserManager::Annotation   ();
use Cpanel::UserManager::Record::Lite ();
use Cpanel::UserManager::Storage      ();

my $allow_demo = {
    allow_demo    => 1,
    needs_feature => 'user_manager',
    needs_role    => { match => 'any', roles => [qw(MailReceive FTP WebDisk)] }
};

my $manage_team_role = { needs_role => { match => 'any', roles => [qw(MailReceive FTP WebDisk)] } };

# Allow api access if it is a team_user
my $mailreceive_ftp_webdisk_role = $ENV{TEAM_USER} ? $manage_team_role : {
    needs_feature => 'user_manager',
    needs_role    => { match => 'any', roles => [qw(MailReceive FTP WebDisk)] }
};

our %API = (
    list_users              => $allow_demo,
    lookup_user             => $allow_demo,
    lookup_service_account  => $allow_demo,
    check_account_conflicts => $allow_demo,
    create_user             => $mailreceive_ftp_webdisk_role,
    edit_user               => $mailreceive_ftp_webdisk_role,
    dismiss_merge           => $mailreceive_ftp_webdisk_role,
    merge_service_account   => $mailreceive_ftp_webdisk_role,
    delete_user             => $mailreceive_ftp_webdisk_role,
    unlink_service_account  => $mailreceive_ftp_webdisk_role,
    change_password         => { allow_demo => 0 },
);

=head1 NAME

UAPI UserManager

=head1 API functions

=head2 UserManager::list_users

This function returns an array of hashes, each of which contains the following
keys and values:

  - alternate_email - String - (May be empty) An alternate email address
  for the user, for password recovery purposes.

  - avatar_url - String - (May be empty) The URL to an image (JPEG, PNG,
  etc.) that may be displayed as the user's profile picture.

  - can_delete - Boolean - If true, the account in question may be deleted. The
  caller may use this attribute to decide which UI elements to show.

  - can_set_password - Boolean - If true, the account in question may have
  its password changed. The caller may use this attribute to decide which
  UI elements to show.

  - can_set_quota - Boolean - If true, the account in question may have its
  quota(s) changed. The caller may use this attribute to decide which UI
  elements to show.

  - dismissed_merge - Boolean - (Only for service accounts) If true, the
  service account has had its merge dismissed. This means that, although
  it shares a name with another account, someone made a decision to keep it
  separate, and not part of a single sub-account.

  - domain - String - The domain under which the account exists. This is
  part of the full_username.

  - webdisk_homedir - String - The home directory for webdisk access, if
  any. This is actually a subdirectory of the cPanel account's hoem directory.

  - full_username - String - The full username used for logging into
  services. This is in <username>@<domain> format.

  - issues - Array - An array of hashes representing problems or other issues
  with the account, each of which contains the following attributes:

      - type - String - 'error', 'warning', or 'info'

      - area - String - (May be empty) The category of the issue. For example,
      'quota' for quota-related issues.

      - service - String - (May be empty) The name of the service affected. May
      be 'email', 'ftp', or 'webdisk'

      - message - String - The message describing the issue in human-readable
      format.

      - used - String - (Only for quota issues) The number of bytes used

      - limit - String - (Only for quota issues) The number of allowed total

  - merge_candidates - Array - An array of hashes, each of which is in the
  same format as another record from this list. For example,
                               each of the merge candidates, if any, will
                               have its own username, domain, etc

  - merged - Boolean - (Only for service accounts) If true, the service
  account has been linked to a sub-account.

  - phone_number - String - (May be empty) A phone number at which the user
  in question may be reached.

  - real_name - String - (May be empty) The user's real name. This may be
  in any format (first and last, first only, last only)

  - services - Hash

      - email - Hash

          - enabled - Boolean - If true, the user has access to email

      - ftp - Hash

          - enabled - Boolean - If true, the user has access to ftp

      - webdisk - Hash

          - enabled - Boolean - If true, the user has access to webdisk

  - special - Boolean - If true, the user is special. Specialness means
  that it is created or managed automatically by the system and is not
  deletable. For example, the anonymous FTP account is special.

  - synced_password - Boolean - (Only for sub-accounts) If true, the passwords
  for all linked services account have been synchronized.

  - type - String - The type of account: 'sub' (a sub-account), 'service'
  (a service account), 'cpanel' (the cPanel account), 'hypothetical'
  (a sub-account that doesn't exist yet, but could exist if a merge were
  performed).

  - username - String - The username of the account, without the domain. For
  example, if the full username is bob@example.com, then this field would have
  "bob" in it.

In the event of a failure, the data will be empty, and the UAPI error field
will be set.

=cut

sub list_users {
    my ( $args, $result ) = @_;

    my $response = Cpanel::UserManager::list_users( flat => $args->get('flat') );
    $result->data($response);

    return 1;
}

=head2 UserManager::create_user

Create a new sub-account.

  - alternate_email - String - (Optional) An alternate email address at
  which the user may be contacted. May be used for automated password
  recovery purposes.

  - avatar_url - String - (Optional) The URL to the user's profile picture
  (JPEG, PNG, etc.)

  - domain - String - The domain at which the user exists. This is part of
  the full_username.

  - password - String - The password to use for the sub-account and any
  service accounts it may have. This is optional when send_invite is true.

  - phone_number - String - (Optional) A phone number at which the user may
  be reached.

  - real_name - String - (Optional) The user's real name. May be in any format
  (first only, last only, first & last, etc.)

  - services.email.enabled - Boolean - If true, grant the user access to email.

  - services.email.quota - String - The email quota in MiB. If not specified,
  an email quota will not be imposed on the user.

  - services.email.send_welcome_email - Boolean - If true, send a welcome email.

  - services.ftp.enabled - Boolean - If true, grant the user access to FTP.

  - services.ftp.homedir - String - The location the files will be
  stored. This should be a relative path representing a subdirectory of the
  cPanel user's home directory.

  - services.webdisk.enabled - Boolean - If true, grant the user access to Web Disk
  (WebDAV).

  - services.webdisk.private - Boolean - If true, the uploaded content will
  only be readable by the owner of the files. This may include any other
  sub-accounts given access to the same directory, but it does not include
  other cPanel accounts on the same server.

  - services.webdisk.homedir - String - The location the files will be
  stored. This should be a relative path representing a subdirectory of the
  cPanel user's home directory.

  - services.webdisk.perms - String - May be either 'ro' for read-only or
  'rw' for read/write.

  - services.webdisk.enabledigest - Boolean - 1: Enable digest authentication
  for this account. 0: Don't enable digest authentication.

  - type - String - The type of account to create. For the purposes of the
  create API, this must always be 'sub'. The attribute is included as a
  settable value in case the create API is later extended to allow creation
  of alternate types of accounts.

  - username - String - The username without the domain. For example, if
  the full username is bob@example.com, then this field will be 'bob'.

  - send_invite - Boolean - 1: Send an email invite to the newly-created user, if
  alternate_email is set, to invite them to set their password. Also, if password
  is undefined, create a random password for the user. 0: Do not send
  an invite. The password parameter must be set.

The usual status and error values are set to indicate success or failure.

=cut

sub create_user ( $args, $result, @ ) {
    my $arguments = $args->{'_args'};

    # Convert services.email => ..., services.ftp => ... into services => { email => ..., ftp => ... }
    Cpanel::ApiUtils::dot_syntax_expand($arguments);

    my $record_obj = eval { Cpanel::UserManager::create_user($arguments) } or do {
        my $err = $@;

        if ( eval { $err->isa('Cpanel::Exception::EntryAlreadyExists') } ) {

            # Do not expose the password or password hash if the entry already exists
            my $user_record = $err->get('entry');
            delete $user_record->{password};
            delete $user_record->{password_hash};
            $result->set_typed_error( 'AlreadyExists', entry => $user_record->TO_JSON() );
        }

        $result->error( 'The system failed to create the user: [_1]', Cpanel::Exception::get_string_no_id($err) );

        return 0;
    };

    $result->data( $record_obj->as_hashref );

    return 1;
}

=head2 UserManager::edit_user

Modify the attributes of a sub-account.

The same attributes you can specify on account creation can also be specified
when editing an account. Make sure to use the correct username and domain, as
this is how the lookup is done. It's currently not possible to change an account's
username or domain.

Any attribute values you specify will replace the existing values for those attributes,
even if yours are blank. However, if you omit any attributes, then the existing value
(if any) will be used.

=cut

sub edit_user {
    my ( $args, $result ) = @_;

    my $attributes = $args->{'_args'};

    Cpanel::ApiUtils::dot_syntax_expand($attributes);

    my $record_obj = eval { Cpanel::UserManager::edit_user($attributes) };
    if ( my $err = $@ ) {
        $result->error( 'The system failed to edit the user: [_1]', $err );
        return 0;
    }

    $result->data( $record_obj->as_hashref );

    return 1;
}

=head2 UserManager::lookup_user

Look up an individual user by guid. This can only be used for looking up sub-accounts,
as they are the only type of account that has a stored guid.

Currently the only allowed lookup field is guid because this is the only one that has
an optimized query. See Cpanel::UserManager::Storage for more about how the lookup
is done.

- guid - String - The guid of the user to look up

Returns a hash containing the attributes of the user in the same format provided by
list_users.

=cut

sub lookup_user {
    my ( $args, $result ) = @_;
    my $found = Cpanel::UserManager::lookup_user( $args->get_length_required('guid') );

    # Populate the merge candidates and dismissed merge candidates
    if ($found) {
        my $full_username = $found->full_username;

        my ( $merge_candidates, $dismissed_merge_candidates ) = Cpanel::UserManager::gather_merge_candidates_for($full_username);

        $found->{'merge_candidates'}           = [ map { $_->as_hashref } @$merge_candidates ];
        $found->{'dismissed_merge_candidates'} = [ map { $_->as_hashref } @$dismissed_merge_candidates ];
    }

    $result->data( $found->as_hashref );
    return 1;
}

=head2 UserManager::lookup_service_account

Look up a service account by full_username and service type.

- full_username - String - The full user@domain username of the account.

- type - String - The service type. May be email, ftp, or webdisk.

If the specified service account is found, returns a hash ref containing the
service account attributes.

=cut

sub lookup_service_account {
    my ( $args, $result ) = @_;
    my $full_username = $args->get('full_username') || die lh()->maketext('You must specify the [asis,full_username] attribute.');
    my $type          = $args->get('type')          || die lh()->maketext('You must specify a service type.');
    if ( !grep { $_ eq $type } ( 'email', 'ftp', 'webdisk' ) ) {
        $result->error('Unsupported service type. You must specify [asis,email], [asis,ftp], or [asis,webdisk].');
        return;
    }

    my $unified_accounts = Cpanel::UserManager::Storage::list_users( ( full_username => $full_username ) );
    my $annotation_list  = Cpanel::UserManager::Storage::list_annotations( ( full_username => $full_username ) );

    my $gather_args = {
        constructor_args => [ annotation_list => $annotation_list ],
        by_user          => $full_username,
    };

    my $accounts = {};
    Cpanel::UserManager::gather_email_accounts( $accounts, $gather_args );
    Cpanel::UserManager::gather_ftp_accounts( $accounts, $gather_args );
    Cpanel::UserManager::gather_webdisk_accounts( $accounts, $gather_args );

    my $user_accounts = $accounts->{$full_username};
    my $has_siblings  = ( scalar @$user_accounts ) > 1 ? 1 : 0;

    my $sub_account_exists = 0;
    if ( 'ARRAY' eq ref $unified_accounts ) {
        if ( @$unified_accounts == 0 ) {
            $sub_account_exists = 0;
        }
        elsif ( @$unified_accounts == 1 ) {
            $sub_account_exists = 1;
        }
        else {
            # Should be impossible...
            $result->error('The system detected multiple [asis,subaccounts] with the same [asis,full_username] attribute.');
            return;
        }
    }

    for my $account (@$user_accounts) {
        if ( $account->services()->{$type}{enabled} ) {
            $account->sub_account_exists($sub_account_exists);
            $account->has_siblings($has_siblings);
            $result->data( $account->as_hashref );
            return 1;
        }
    }

    $result->error('The specified service account does not exist.');
    return;
}

=head2 UserManager::dismiss_merge

For a service account which is being shown as a merge candidate for a sub-account or hypothetical
sub-account, mark the merge as dismissed. This means that the service account will be treated as
independent and will no longer be considered a merge candidate. If any sub-account exists with
th same name, this will also impose the limitation on that account that it can't enable the
service in question, since the name is already taken by the independent service account.

  - username - String - The username (without the domain) of the service account

  - domain - String - The domain of the service account

  - services.email.dismiss - Boolean - Dismiss the merge of the email service account

  - services.ftp.dismiss - Boolean - Dismiss the merge of the FTP service account

  - services.webdisk.dismiss - Boolean - Dismiss the merge of the Web Disk service account

The usual status and error values are set to indicate success or failure.

=cut

sub dismiss_merge {
    my ( $args, $result ) = @_;

    my $arguments = $args->{'_args'};
    Cpanel::ApiUtils::dot_syntax_expand($arguments);

    my $username = $arguments->{username} || die lh()->maketext( 'You must specify “[_1]” to dismiss a service account merge.', 'username' );
    my $domain   = $arguments->{domain}   || die lh()->maketext( 'You must specify “[_1]” to dismiss a service account merge.', 'domain' );
    my $services = $arguments->{services};
    'HASH' eq ref $services or die lh()->maketext( 'You must specify “[_1]” to dismiss a service account merge.', 'services.___.merge' );

    foreach my $service ( sort keys %$services ) {
        next unless $services->{$service}{dismiss};

        my $annotation = Cpanel::UserManager::Annotation->new(
            {
                username        => $username,
                domain          => $domain,
                service         => $service,
                dismissed_merge => 1,
            }
        );

        Cpanel::UserManager::Storage::store($annotation);
    }

    return 1;
}

=head2 UserManager::merge_service_account

For a service account which is being shown as a merge candidate for a sub-account or hypothetical
sub-account, mark the service account as merged/linked with a sub-account.

If the target sub-account already exists, it will be used. If it doesn't already exist, it will
be created.

The sub-account you want to link the service account with has the same username and domain, so
there's no need to specify the name of the sub-account.

  - username - String - The username (without the domain) of the service account

  - domain - String - The domain of the service account

  - services.email.merge - Boolean - If true, merge the email service account

  - services.ftp.merge - Boolean - If true, merge the FTP service account

  - services.webdisk.merge - Boolean - If true, merge the Web Disk service account

The usual status and error values are set to indicate success or failure.

=cut

sub merge_service_account {
    my ( $args, $result ) = @_;

    my $arguments = $args->{'_args'};
    Cpanel::ApiUtils::dot_syntax_expand($arguments);
    my $username = $arguments->{username} || die lh()->maketext( 'You must specify “[_1]” to merge a service account.', 'username' );
    my $domain   = $arguments->{domain}   || die lh()->maketext( 'You must specify “[_1]” to merge a service account.', 'domain' );
    my $services = $arguments->{services};

    'HASH' eq ref $services or die lh()->maketext( 'You must specify “[_1]” to merge a service account.', 'services.___.merge' );
    require Cpanel::Validate::Domain;
    Cpanel::Validate::Domain::valid_wild_domainname($domain) || die lh()->maketext( 'Invalid value for “[_1]”.', 'domain' );
    require Cpanel::Validate::EmailLocalPart;
    Cpanel::Validate::EmailLocalPart::is_valid($username) || die lh()->maketext( 'Invalid value for “[_1]”.', 'username' );

    my $n_merged;
    foreach my $service ( sort keys %$services ) {
        next unless $services->{$service}{merge};
        ++$n_merged;

        # Check to see that a service account actually exists, and
        # grab the password that we might need later anyway.
        my $current_service_password_hash = Cpanel::UserManager::lookup_service_password_hash( $username, $domain, $service );

        # Create or update the user
        my $record_obj = Cpanel::UserManager::Storage::lookup_user( username => $username, domain => $domain );
        if ($record_obj) {
            $record_obj->synced_password(0);
            Cpanel::UserManager::Storage::amend($record_obj);
        }
        else {

            # If this merge operation will be the one that creates the sub-account for the first time, and there
            # are no other service accounts being merged as part of the same operation, then we will inherit the
            # password hash from the service account for use with the sub-account.
            my $inherit_password_hash = ( keys(%$services) == 1 );

            if ($inherit_password_hash) {
                $record_obj = Cpanel::UserManager::create_user(
                    {
                        username        => $username,
                        domain          => $domain,
                        password_hash   => $current_service_password_hash,
                        synced_password => 1,
                    }
                );
            }
            else {
                my $temporary_password = Cpanel::Rand::Get::getranddata(64);

                $record_obj = Cpanel::UserManager::create_user(
                    {
                        username        => $username,
                        domain          => $domain,
                        password        => $temporary_password,
                        synced_password => 0
                    }
                );
            }
        }

        # Update the annotations
        my $annotation = Cpanel::UserManager::Annotation->new(
            {
                username   => $username,
                domain     => $domain,
                service    => $service,
                merged     => 1,
                owner_guid => $record_obj->guid,
            }
        );

        Cpanel::UserManager::Storage::store($annotation);
    }

    if ( !$n_merged ) {
        die lh()->maketext('You must specify at least one service account to merge.') . "\n";
    }

    my $list = Cpanel::UserManager::list_users();
    my ($new_parent) = grep { $_->{username} eq $username and $_->{domain} eq $domain and $_->{type} eq 'sub' } @$list;
    $result->data($new_parent);
    return 1;
}

=head2 UserManager::delete_user

Deletes a sub-account.

  - username - String - The username (without the domain) of the sub-account to delete.

  - domain - String - The domain of the sub-account to delete.

The usual status and error values are set to indicate success or failure.

If un-merged service accounts with the same username exist, they will be returned (exactly like
in list_users--a single account of type "service" or a "hypothetical" with merge candidates.)

=cut

sub delete_user {
    my ( $args, $result ) = @_;

    my ( $username, $domain ) = $args->get_length_required( 'username', 'domain' );
    my $new_data = Cpanel::UserManager::delete_user( username => $username, domain => $domain );

    $result->data($new_data);
    return 1;
}

=head2 UserManager::check_account_conflicts

Checks to see if there is a user account or service accounts that conflict
with the given full_username

- full_username - String - The full user@domain username of the account.

Returns:

- conflict - Boolean - whether or not a conflicting account exists

- accounts - Hashref - if unmerged service accounts exist, a "hypothetical" account, with an added element:

  - dismissed_merge_candidates - Hashref - service accounts that have already been dismissed previously.

=cut

sub check_account_conflicts {
    my ( $args, $result ) = @_;
    my $full_username = $args->get('full_username') || die lh()->maketext('You must specify the [asis,full_username] attribute.');
    my ( $username, $domain ) = split( '@', $full_username );

    my $response              = { 'conflict' => 0 };
    my $skip_checking_service = 0;

    my $accounts = Cpanel::UserManager::Storage::list_users( ( full_username => $full_username ) );
    if ( 'ARRAY' eq ref $accounts ) {
        if ( @$accounts > 0 ) {    # a conflicting account exists
            $response = { 'conflict' => 1 };
            $skip_checking_service++;
        }
    }

    if ( !$skip_checking_service ) {

        my ( $merge_candidates, $dismissed_merge_candidates ) = Cpanel::UserManager::gather_merge_candidates_for($full_username);
        if ( @$merge_candidates || @$dismissed_merge_candidates ) {
            my $hypothetical = Cpanel::UserManager::Record::Lite->new(
                {
                    type                       => 'hypothetical',
                    username                   => $username,
                    domain                     => $domain,
                    merge_candidates           => [ map { $_->as_hashref } @$merge_candidates ],
                    dismissed_merge_candidates => [ map { $_->as_hashref } @$dismissed_merge_candidates ],
                }
            );
            $response->{'accounts'} = $hypothetical->as_hashref;
        }
    }

    $result->data($response);
    return 1;
}

=head2 UserManager::unlink_service_account

Unlinks a service account from a sub-account.

  - username - String - The username (without the domain) of the service account to unlink.

  - domain - String - The domain of the service account to unlink.

  - service - String - The service to unlink: 'webdisk','email', or 'ftp'

  - dismiss - Boolean - (optional) If true, also mark the service account as dismissed, so it
                        will not show up as a merge candidate.

The usual status and error values are set to indicate success or failure.

=cut

sub unlink_service_account {
    my ( $args, $result ) = @_;

    my $username = $args->get('username') || die lh()->maketext( 'You must specify the “[_1]” to unlink a service account.', 'username' );
    my $domain   = $args->get('domain')   || die lh()->maketext( 'You must specify the “[_1]” to unlink a service account.', 'domain' );
    my $service  = $args->get('service')  || die lh()->maketext( 'You must specify the “[_1]” to unlink a service account.', 'service' );
    my $dismiss  = $args->get('dismiss');    # optional

    my $record_obj = Cpanel::UserManager::Storage::lookup_user( username => $username, domain => $domain );
    if ( !$record_obj ) {
        $result->error('The user does not exist.');
        return;
    }

    my $delete_ok = Cpanel::UserManager::Storage::delete_annotation( $record_obj, $service );
    if ( !$delete_ok ) {
        $result->error( 'The system failed to delete the annotation record for the [_1] account “[_2]@[_3]”', $service, $username, $domain );
        return;
    }

    if ($dismiss) {
        my $annotation = Cpanel::UserManager::Annotation->new(
            {
                username        => $username,
                domain          => $domain,
                service         => $service,
                dismissed_merge => 1,
            }
        );

        Cpanel::UserManager::Storage::store($annotation);
    }

    return 1;
}

=head2 UserManager::change_password

For now only support updating the password for the main user.
Use edit_user to alter additional user password.

=cut

sub change_password ( $args, $result ) {

    my ( $oldpass, $newpass ) = $args->get_length_required(qw{ oldpass newpass });
    my $enablemysql = $args->get('enablemysql') // 0;

    require Cpanel::Passwd;

    my $api2_reply = Cpanel::Passwd::api2_change_password(    #
        oldpass     => $oldpass,                              #
        newpass     => $newpass,                              #
        enablemysql => $enablemysql,                          #
    );

    return $result->error("Unexpected error while changing password.") unless ref $api2_reply eq 'ARRAY'    #
      && ref $api2_reply->[0] eq 'HASH';

    my $r = $api2_reply->[0];

    if ( !$r->{status} ) {
        return $result->error( "Failed to change password: " . ( $r->{statustxt} // '' ) );
    }

    return $result->data(q[Password Changed]);
}

1;
