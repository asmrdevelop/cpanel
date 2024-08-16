package Cpanel::Security::Authn::User::Modify;

# cpanel - Cpanel/Security/Authn/User/Modify.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::AcctUtils::Domain             ();
use Cpanel::AcctUtils::Lookup             ();
use Cpanel::AcctUtils::Account            ();
use Cpanel::App                           ();
use Cpanel::Autodie                       ();
use Cpanel::LoadModule                    ();
use Cpanel::Exception                     ();
use Cpanel::Security::Authn::Config       ();
use Cpanel::Security::Authn::User         ();
use Cpanel::Transaction::File::JSONReader ();
use Cpanel::Validate::OpenIdConnect       ();
use Cpanel::Validate::AuthProvider        ();
use Cpanel::Validate::FilesystemNodeName  ();
use Cpanel::Validate::LineTerminatorFree  ();
use Cpanel::AcctUtils::Lookup::Webmail    ();

use Try::Tiny;

our $VERSION = '1.0';

###########################################################################
#
# Method:
#   add_authn_link_for_user
#
# Description:
#   This function is used to add an authentication link from a user to a remote authority.
#   NOTE: Until 11.56, this function will remove any matching link from other users. In other words,
#         if you try to link a google account already linked to the account 'bob' to the account 'alice',
#         the account 'bob' will have the google account unlinked from it.
#
# Parameters:
#   $user          - The user (cPanel user/reseller or email account) to get the links for.
#   $protocol      - The protocol used by the remote authority (such as openid_connect, or any other protocol we eventually support)
#   $provider_name - The name of the provider giving access to the remote authority.
#   $subject_unique_identifier - Whatever identifying information we're using to link an external account to a cPanel user
#   $user_info     - A hashref of the form:
#                    {
#                       preferred_username => the more human readable identifying information for the external account
#                       link_time          => (optional) the time the link was first created, if not passed the current time will be used.
#                    }
#
# Exceptions:
#   Cpanel::Exception::MissingParameter - Thrown if any of the parameters are not passed.
#   Cpanel::Exception::InvalidParameter - Thrown if any of the parameters are not valid.
#   Anything Cpanel::Validate::OpenIdConnect::check_user_exists_or_die can throw.
#   Anything Cpanel::Transaction::File::JSON* can throw.
#   Anything Cpanel::Security::Authn::LinkDB::save_links_for_user can throw.
#
# Returns:
#   The method returns 1 on success or throws an exception if it failed.
#
sub add_authn_link_for_user {
    my ( $user, $protocol, $provider_name, $subject_unique_identifier, $user_info ) = @_;

    # These will die if invalid
    Cpanel::Validate::OpenIdConnect::check_protocol_or_die($protocol);
    Cpanel::Validate::AuthProvider::check_provider_name_or_die($provider_name);
    _validate_provider_is_enabled_for_at_least_one_service( $protocol, $provider_name );
    Cpanel::Validate::OpenIdConnect::check_subject_unique_identifier_or_die($subject_unique_identifier);
    Cpanel::Validate::OpenIdConnect::check_hashref_or_die( $user_info, 'user_info' );
    die Cpanel::Exception::create( 'MissingParameter', [ name => 'user' ] ) if !length $user;
    Cpanel::Validate::OpenIdConnect::check_user_exists_or_die($user);

    if ( $user_info && length $user_info->{'preferred_username'} ) {
        Cpanel::Validate::LineTerminatorFree::validate_or_die( $user_info->{'preferred_username'} );
        Cpanel::Validate::FilesystemNodeName::validate_or_die( $user_info->{'preferred_username'} );
    }
    $user_info->{'link_time'} ||= time();

    my ( $transaction, $data ) = _get_authn_user_db_transaction_and_data($user);

    $data->{'__VERSION'} = $VERSION;
    $data->{$protocol}{$provider_name}{$subject_unique_identifier} = $user_info;

    $transaction->set_data($data);

    $transaction->save_or_die();

    require Cpanel::Security::Authn::LinkDB;
    my $link_db = Cpanel::Security::Authn::LinkDB->new(
        'protocol'      => $protocol,
        'provider_name' => $provider_name
    )->save_links_for_user(
        'user'  => $user,
        'links' => $data->{$protocol}{$provider_name}
    );

    _notify_account_link_if_enabled( $user, $provider_name, $user_info->{'preferred_username'} );

    $transaction->close_or_die();

    $transaction = undef;

    return 1;
}

###########################################################################
#
# Method:
#   remove_authn_link_for_user
#
# Description:
#   This function is used to remove an authentication link from a user to a remote authority.
#
# Parameters:
#   $user          - The user (cPanel user/reseller or email account) to get the links for.
#   $protocol      - The protocol used by the remote authority (such as openid_connect, or any other protocol we eventually support)
#   $provider_name - The name of the provider giving access to the specific remote authority.
#
# Exceptions:
#   Cpanel::Exception::MissingParameter if user is not passed.
#   Anything Cpanel::Validate::OpenIdConnect methods check_protocol, check_provider_name, check_subject_unique_identifier, or check_user_exists can throw.
#   Anything Cpanel::Transaction::File::JSON* can throw.
#   Anything Cpanel::Security::Authn::LinkDB::save_links_for_user can throw.
#
# Returns:
#   The method returns 1 on success or throws an exception if it failed.
#
sub remove_authn_link_for_user {
    my ( $user, $protocol, $provider_name, $subject_unique_identifier ) = @_;

    # These will die if invalid
    Cpanel::Validate::OpenIdConnect::check_protocol_or_die($protocol);
    Cpanel::Validate::AuthProvider::check_provider_name_or_die($provider_name);
    Cpanel::Validate::OpenIdConnect::check_subject_unique_identifier_or_die($subject_unique_identifier);
    die Cpanel::Exception::create( 'MissingParameter', [ name => 'user' ] ) if !length $user;
    Cpanel::Validate::OpenIdConnect::check_user_exists_or_die($user);

    my ( $transaction, $data ) = _get_authn_user_db_transaction_and_data($user);

    if ( !exists $data->{$protocol}{$provider_name}{$subject_unique_identifier} ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The value of the parameter “[_1]” is not valid for this user.', ['subject_unique_identifier'] );
    }

    _remove_authn_links_for_user(
        {
            user                       => $user,
            protocol                   => $protocol,
            provider_name              => $provider_name,
            subject_unique_identifiers => [$subject_unique_identifier],
            transaction                => $transaction,
            data                       => $data
        }
    );

    $transaction->set_data($data);

    $transaction->save_and_close_or_die();

    $transaction = undef;

    return 1;
}

###########################################################################
#
# Method:
#   remove_all_authn_links_for_system_user_and_subusers
#
# Description:
#   This function is used to remove all authentication links to external accounts for a system user.
#   We could probably make a more direct way to do this, but atm this should be sufficient.
#   We can reevaluate if this proves to be too slow in practice.
#
# Parameters:
#   $system_user          - The cPanel user to remove all authn links for.
#
# Exceptions:
#   Cpanel::Exception::MissingParameter - Thrown if the user parameter is not passed.
#   Anything Cpanel::AcctUtils::Account::accountexists_or_die can throw.
#   Cpanel::Exception::Collection - Thrown if any errors occur in the removal of the system user or subuser link data.
#                                   This means the function will attempt to do its best at removing everything, but will
#                                   roll up all the exceptions into one collection (past the initial validation).
#
# Returns:
#   The method returns 1 on success or throws an exception if it failed.
#
#
#
sub remove_all_authn_links_for_system_user_and_subusers {
    my ($system_user) = @_;

    die Cpanel::Exception::create( 'MissingParameter', [ name => 'system_user' ] ) if !length $system_user;
    Cpanel::AcctUtils::Account::accountexists_or_die($system_user);

    my @users_to_remove = Cpanel::Security::Authn::User::get_all_link_enabled_users_for_system_user($system_user);

    my @exceptions;
    try {
        remove_all_authn_links_for_users( \@users_to_remove );
    }
    catch {
        push @exceptions, $_;
    };

    try {
        require File::Path;
        File::Path::rmtree( Cpanel::Security::Authn::User::get_user_db_directory($system_user) );
    }
    catch {
        push @exceptions, $_;
    };

    if (@exceptions) {
        die Cpanel::Exception::create( 'Collection', 'The system encountered the following [numerate,_1,error,errors] while it tried to remove the link data for the system user “[_2]” and its sub-users.', [ scalar @exceptions, $system_user ], { exceptions => \@exceptions } );
    }

    return 1;
}

###########################################################################
#
# Method:
#   remove_all_authn_links_for_users
#
# Description:
#   This function is used to remove all authentication links to external accounts for specified users.
#   This is useful for removing a group of subusers or all the authn user files for a system user + sub users.
#
# Parameters:
#   $user_ar          - An arrayref of usernames to remove the external authn links for.
#
# Exceptions:
#   Cpanel::Exception::MissingParameter - Thrown if the user_ar parameter is not passed.
#   Cpanel::Exception::Collection - Thrown if any errors occur in the removal of the user link data.
#                                   This means the function will attempt to do its best at removing everything, but will
#                                   roll up all the exceptions into one collection (past the initial validation).
#
# Returns:
#   The method returns 1 on success or throws an exception if it failed.
#
sub remove_all_authn_links_for_users {
    my ($user_ar) = @_;

    die Cpanel::Exception::create( 'MissingParameter', [ name => 'user_ar' ] ) if !$user_ar;

    my @exceptions;
    my $provider_to_users_map = {};
    my $todo_cr               = sub {
        my ( $user, $protocol, $provider ) = @_;

        if ( $provider_to_users_map->{$protocol}{$provider} ) {
            push @{ $provider_to_users_map->{$protocol}{$provider} }, $user;
        }
        else {
            $provider_to_users_map->{$protocol}{$provider} = [$user];
        }
    };

    for my $user (@$user_ar) {

        my $user_links;
        try {
            $user_links = Cpanel::Security::Authn::User::get_authn_links_for_user($user);
        }
        catch {
            push @exceptions, $_;
        };

        next if !$user_links || !scalar keys %$user_links;

        _operate_on_user_links( $user, $user_links, $todo_cr );
    }

    require Cpanel::Security::Authn::LinkDB;
    for my $protocol ( keys %$provider_to_users_map ) {
        for my $provider_name ( keys %{ $provider_to_users_map->{$protocol} } ) {
            try {
                Cpanel::Security::Authn::LinkDB->new( 'protocol' => $protocol, 'provider_name' => $provider_name )->remove_all_links_for_users(
                    'users' => $provider_to_users_map->{$protocol}{$provider_name},
                );
            }
            catch {
                push @exceptions, $_;
            };
        }
    }

    for my $link_user (@$user_ar) {
        try {
            Cpanel::Autodie::unlink_if_exists( Cpanel::Security::Authn::User::get_db_path($link_user) );
        }
        catch {
            push @exceptions, $_;
        };
    }

    if (@exceptions) {
        die Cpanel::Exception::create( 'Collection', 'The system encountered the following [numerate,_1,error,errors] while it tried to remove the link data for [list_and_quoted,_2].', [ scalar @exceptions, $user_ar ], { exceptions => \@exceptions } );
    }

    return 1;
}

###########################################################################
#
# Method:
#   change_system_user_name
#
# Description:
#   This function is used to change the system user's name during a username change. This will
#   rename their /var/cpanel/authn/links/users/$user/ directory and database file. It will also
#   alter the user's links in the authn provider link cache databases (/var/cpanel/authn/links/openid_connect/login/*)
#
# Parameters:
#   $old_user  - The previous username
#   $new_user  - The new username
#
# Exceptions:
#   Cpanel::Exception::MissingParameter - Thrown if the old_user or new_user parameters are not passed.
#   Anything Cpanel::AcctUtils::Account::accountexists_or_die can throw.
#   Cpanel::Exception::Collection - Thrown if any errors occur in changing the user's authn link directory, database
#                                   file, or while altering the authn provider link cache databases.
#
# Returns:
#   The method returns 1 on success or throws an exception if it failed.
#
sub change_system_user_name {
    my ( $old_user, $new_user ) = @_;

    die Cpanel::Exception::create( 'MissingParameter', [ name => 'old_user' ] ) if !length $old_user;
    die Cpanel::Exception::create( 'MissingParameter', [ name => 'new_user' ] ) if !length $new_user;
    Cpanel::AcctUtils::Account::accountexists_or_die($old_user);

    my $links = Cpanel::Security::Authn::User::get_authn_links_for_user($old_user);

    my $old_user_dir = Cpanel::Security::Authn::User::get_user_db_directory($old_user);
    my $new_user_dir = Cpanel::Security::Authn::User::get_user_db_directory($new_user);

    if ( Cpanel::Autodie::rename_if_exists( $old_user_dir, $new_user_dir ) ) {

        my $old_user_db = $new_user_dir . '/' . Cpanel::Security::Authn::User::get_db_file_name($old_user);
        my $new_user_db = Cpanel::Security::Authn::User::get_db_path($new_user);

        if ( Cpanel::Autodie::rename_if_exists( $old_user_db, $new_user_db ) ) {
            my $username_map = { $old_user => $new_user };
            require Cpanel::Security::Authn::LinkDB;

            my @exceptions;
            _operate_on_user_links(
                $old_user,
                $links,
                sub {
                    my ( $user, $protocol, $provider ) = @_;

                    try {
                        Cpanel::Security::Authn::LinkDB->new( 'protocol' => $protocol, 'provider_name' => $provider )->change_usernames( 'username_map' => $username_map );
                    }
                    catch {
                        push @exceptions, $_;
                    };
                }
            );

            if (@exceptions) {
                die Cpanel::Exception::create( 'Collection', 'The system encountered the following [numerate,_1,error,errors] while it tried to modify the external authentication link database to change the system username from “[_2]” to “[_3]”.', [ scalar @exceptions, $old_user, $new_user ], { exceptions => \@exceptions } );
            }
        }
    }

    return 1;
}

###########################################################################
#
# Method:
#   change_subuser_domains_for_system_user
#
# Description:
#   This function is used to change the usernames of subaccounts that match a changing domain
#   during a domain change. This will rename their authn link database file and will alter
#   the user's links in the authn provider link cache databases (/var/cpanel/authn/links/openid_connect/login/*)
#
# Parameters:
#   $system_user    - The system username of the user the primary domain is changing on.
#   $domain_mapping - A hashref mapping of changing primary, addon, sub, and parked domains that are changing due to
#                     the primary domain changing. The hashref should look like:
#                     {
#                        formerprimary.tld => newprimary.tld,
#                        sub.formerprimary.tld => sub.newprimary.tld,
#                     }
#
# Exceptions:
#   Cpanel::Exception::MissingParameter - Thrown if the any of the parameters are not passed.
#   Anything Cpanel::AcctUtils::Account::accountexists_or_die can throw.
#   Cpanel::Exception::Collection - Thrown if any errors occur in changing the user's authn link database
#                                   file, or while altering the authn provider link cache databases.
#
# Returns:
#   The method returns 1 on success or throws an exception if it failed.
#
sub change_subuser_domains_for_system_user {
    my ( $system_user, $domain_mapping ) = @_;

    die Cpanel::Exception::create( 'MissingParameter', [ name => 'system_user' ] ) if !length $system_user;
    Cpanel::Validate::OpenIdConnect::check_hashref_or_die($domain_mapping);
    Cpanel::AcctUtils::Account::accountexists_or_die($system_user);

    my @link_enabled_users = Cpanel::Security::Authn::User::get_all_link_enabled_users_for_system_user($system_user);
    return 1 if !scalar @link_enabled_users;

    my $user_db_directory = Cpanel::Security::Authn::User::get_user_db_directory($system_user);

    my @exceptions;
    my $username_map = {};
    my $todo_cr      = sub {
        my ( $user, $protocol, $provider, undef, $new_username ) = @_;

        $username_map->{$protocol}{$provider}{$user} = $new_username;
    };

    for my $link_user (@link_enabled_users) {
        next if !Cpanel::AcctUtils::Lookup::Webmail::is_strict_webmail_user($link_user);

        my ( $user, $domain ) = split( '@', $link_user, 2 );
        next if !$domain_mapping->{$domain};

        my $new_username = $user . '@' . $domain_mapping->{$domain};

        my $user_links;
        try {
            $user_links = _get_authn_links_for_user_no_validation( $system_user, $link_user );
        }
        catch {
            push @exceptions, $_;
        };

        _operate_on_user_links( $link_user, $user_links, $todo_cr, $new_username );

        my $old_db_path = "$user_db_directory/" . Cpanel::Security::Authn::User::get_db_file_name($link_user);
        my $new_db_path = "$user_db_directory/" . Cpanel::Security::Authn::User::get_db_file_name($new_username);

        try {
            Cpanel::Autodie::rename( $old_db_path, $new_db_path );
        }
        catch {
            push @exceptions, $_;
        };
    }

    require Cpanel::Security::Authn::LinkDB;
    for my $protocol ( keys %$username_map ) {
        for my $provider_name ( keys %{ $username_map->{$protocol} } ) {
            try {
                Cpanel::Security::Authn::LinkDB->new( 'protocol' => $protocol, 'provider_name' => $provider_name )->change_usernames( 'username_map' => $username_map->{$protocol}{$provider_name} );
            }
            catch {
                push @exceptions, $_;
            };
        }
    }

    if (@exceptions) {
        die Cpanel::Exception::create( 'Collection', 'The system encountered the following [numerate,_1,error,errors] while it tried to modify the external authentication link database to change domain names for the user “[_2]”.', [ scalar @exceptions, $system_user ], { exceptions => \@exceptions } );
    }

    return 1;
}

sub _notify_account_link_if_enabled {
    my ( $user, $provider_name, $preferred_username ) = @_;

    my $system_user = $user;
    if ( Cpanel::AcctUtils::Lookup::Webmail::is_strict_webmail_user($user) ) {
        $system_user = Cpanel::AcctUtils::Lookup::get_system_user($user);
    }

    Cpanel::LoadModule::load_perl_module('Cpanel::ContactInfo');
    my $cinfo = Cpanel::ContactInfo::get_contactinfo_for_user($system_user);
    return if !$cinfo->{'notify_account_authn_link'};

    return _send_account_link_notification( $system_user, $user, $provider_name, $preferred_username );
}

sub _send_account_link_notification {
    my ( $system_user, $to, $provider_name, $preferred_username ) = @_;

    my $domain = Cpanel::AcctUtils::Domain::getdomain($system_user);

    require Cpanel::Security::Authn::OpenIdConnect;
    my $provider_obj = Cpanel::Security::Authn::OpenIdConnect::get_openid_provider( $Cpanel::App::appname, $provider_name );

    require Cpanel::Notify;
    Cpanel::Notify::notification_class(
        'class'            => 'Security::AuthnMethodLinkedToAccount',
        'application'      => 'Security::AuthnMethodLinkedToAccount',
        'constructor_args' => [
            username                          => $system_user,
            to                                => $to,
            user                              => $to,
            user_domain                       => $domain,
            notification_targets_user_account => ( $system_user ne 'root' ? 1 : 0 ),
            provider_display_name             => $provider_obj->get_provider_display_name(),
            preferred_username                => $preferred_username,
            origin                            => $Cpanel::App::appname,
            source_ip_address                 => $ENV{'REMOTE_ADDR'},
            interval                          => 1,
        ]
    );

    return 1;
}

sub _get_authn_user_db_transaction_and_data {
    my ($user) = @_;

    my $transaction = _get_authn_user_db_transaction($user);
    my $data        = $transaction->get_data();
    $data = {} if ref $data eq 'SCALAR' && !$$data;    # Data file uninitialized, initialze to an empty hash

    return ( $transaction, $data );
}

sub _get_authn_user_db_transaction {
    my ($user) = @_;

    my $system_user = Cpanel::AcctUtils::Lookup::get_system_user($user);

    require Cpanel::Transaction::File::JSON;
    return Cpanel::Transaction::File::JSON->new(
        path        => Cpanel::Security::Authn::User::get_db_path($user),
        permissions => 0640,
        ownership   => [ 0, $system_user ],
    );
}

sub _remove_authn_links_for_user {
    my ($opts) = @_;

    my ( $user, $protocol, $provider_name, $subject_unique_identifiers, $transaction, $data ) =
      @{$opts}{qw( user protocol provider_name subject_unique_identifiers transaction data )};

    delete @{ $data->{$protocol}{$provider_name} }{@$subject_unique_identifiers};

    if ( !scalar keys %{ $data->{$protocol}{$provider_name} } ) {
        delete $data->{$protocol}{$provider_name};
        if ( !scalar keys %{ $data->{$protocol} } ) {
            delete $data->{$protocol};
        }
    }

    # Remove the links
    my $sync_ref = { map { $_ => undef } @$subject_unique_identifiers };

    require Cpanel::Security::Authn::LinkDB;
    Cpanel::Security::Authn::LinkDB->new(
        'protocol'      => $protocol,
        'provider_name' => $provider_name
    )->save_links_for_user(
        'user'  => $user,
        'links' => $sync_ref
    );

    return;
}

sub _operate_on_user_links {
    my ( $user, $user_links, $to_do_cr, @extra_args ) = @_;

    return if !$user_links || !scalar keys %$user_links;

    for my $protocol ( keys %$user_links ) {
        for my $provider ( keys %{ $user_links->{$protocol} } ) {
            $to_do_cr->( $user, $protocol, $provider, $user_links->{$protocol}{$provider}, @extra_args );
        }
    }

    return;
}

sub _validate_provider_is_enabled_for_at_least_one_service {
    my ( $protocol, $provider_name ) = @_;
    if ( $protocol eq 'openid_connect' ) {
        require Cpanel::Security::Authn::OpenIdConnect;
        for my $svc (@Cpanel::Security::Authn::Config::ALLOWED_SERVICES) {
            my $svc_provider_data = Cpanel::Security::Authn::OpenIdConnect::get_enabled_openid_connect_providers($svc);
            if ( $svc_provider_data->{$provider_name} ) {
                return 1;
            }
        }
        die Cpanel::Exception::create( 'InvalidParameter', 'The provider “[_1]” is not enabled for any services with [asis,OpenID Connect] authentication.', [$provider_name] );
    }

    # Should never be reached
    die "_validate_provider_is_enabled_for_at_least_one_service only supports “openid_connect”";
}

sub _get_authn_links_for_user_no_validation {
    my ( $system_user, $user ) = @_;

    my $transaction = _get_authn_user_db_reader_no_validation( $system_user, $user );
    return Cpanel::Security::Authn::User::get_authn_links_from_transaction($transaction);
}

sub _get_authn_user_db_reader_no_validation {
    my ( $system_user, $user ) = @_;

    my $user_dir = Cpanel::Security::Authn::User::get_user_db_directory($system_user);
    my $db_file  = Cpanel::Security::Authn::User::get_db_file_name($user);

    return Cpanel::Transaction::File::JSONReader->new(
        path => "$user_dir/$db_file",
    );
}

1;
