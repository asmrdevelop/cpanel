package Cpanel::Security::Authn::User;

# cpanel - Cpanel/Security/Authn/User.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::LoadModule                    ();
use Cpanel::AcctUtils::Lookup::Webmail    ();
use Cpanel::AcctUtils::Account            ();
use Cpanel::Context                       ();
use Cpanel::Exception                     ();
use Cpanel::FileUtils::Dir                ();
use Cpanel::Security::Authn::Config       ();
use Cpanel::Transaction::File::JSONReader ();
use Cpanel::Validate::OpenIdConnect       ();
use Cpanel::Validate::AuthProvider        ();
use Cpanel::Validate::FilesystemNodeName  ();

use Try::Tiny;

our $VERSION = '1.0';
my %_CREATED_STORAGE_DIRS;

#+------------------------------------------------------------------------------------
# The purpose of this module is to provide user management features for the
# pluggable external authentication system. This module is meant to be used by
# root.
#+------------------------------------------------------------------------------------

###########################################################################
#
# Method:
#   get_authn_links_for_user
#
# Description:
#   This function gets the value of a specific authentication link to a remote authority.
#
# Parameters:
#   $user - The user (cPanel user/reseller or email account) to get the links for.
#
# Exceptions:
#   Cpanel::Exception::MissingParameter - Thrown if user is not passed.
#   Anything Cpanel::Validate::OpenIdConnect::check_user_exists_or_die can throw.
#   Anything Cpanel::Validate::FilesystemNodeName::validate_or_die can throw.
#   Anything Cpanel::Transaction::File::JSON* can throw.
#
# Returns:
#   This method returns all the identifying information that links the cPanel account to any number of external accounts.
# {
#     protocol => {
#         provider_name => {
#             subject_unique_identifier => Hashref of some user information (currently { preferred_username => The human readable username for the external account })
#         },
# }
#
sub get_authn_links_for_user {
    my ($user) = @_;

    die Cpanel::Exception::create( 'MissingParameter', [ name => 'user' ] ) if !length $user;
    Cpanel::Validate::FilesystemNodeName::validate_or_die($user);
    Cpanel::Validate::OpenIdConnect::check_user_exists_or_die($user);

    return _get_authn_links_for_user($user);
}

###########################################################################
#
# Method:
#   get_all_link_enabled_users_for_system_user
#
# Description:
#   This function gets all the users under (and including) a system user that have linked their account
#   with an external authentication provider. It gets this information by enumerating the link dbs inside
#   the system user's /var/cpanel/authn/links/users/$user/ dir. This must be called in list context.
#
# Parameters:
#   $system_user - The cPanel user to get the list of users who have linked their accounts.
#
# Exceptions:
#   Cpanel::Exception::MissingParameter - Thrown if system_user is not passed.
#   Anything Cpanel::AcctUtils::Account::accountexists_or_die can throw.
#   Cpanel::Exception::ContextError     - Thrown if the function is called in scalar context.
#   Anything Cpanel::Validate::FilesystemNodeName::validate_or_die can throw.
#
# Returns:
#   A list of usernames which have external authentication link databases in the user's authn link directory.
#   This can include the system user itself.
#   ( 'bob', 'bob@bobshosting.tld', 'frankhatesbob@bobsucks.tld' )
#
sub get_all_link_enabled_users_for_system_user {
    my ($system_user) = @_;

    Cpanel::Context::must_be_list();

    die Cpanel::Exception::create( 'MissingParameter', [ name => 'system_user' ] ) if !length $system_user;
    Cpanel::Validate::FilesystemNodeName::validate_or_die($system_user);
    Cpanel::AcctUtils::Account::accountexists_or_die($system_user);

    return @{ _get_link_directory_usernames($system_user) };
}

###########################################################################
#
# Method:
#   get_all_authn_links_for_system_user_and_subusers
#
# Description:
#   This function gets all the external authentication links for users under (and including) a system user.
#
# Parameters:
#   $system_user - The cPanel user to get the external authentication links for their account and any linked email accounts.
#
# Exceptions:
#   Cpanel::Exception::MissingParameter - Thrown if system_user is not passed.
#   Anything Cpanel::AcctUtils::Account::accountexists_or_die can throw.
#   Anything Cpanel::Validate::FilesystemNodeName::validate_or_die can throw.
#   Anything get_authn_links_for_user can throw.
#
# Returns:
#   A hashref of users (the system user and linked email accounts the user may own) and their external authentication links:
#   {
#      user => {
#         protocol => {
#            provider_name => {
#               subject_unique_identifier => Hashref of some user information (currently { preferred_username => The human readable username for the external account })
#            },
#      }
#   }
#
sub get_all_authn_links_for_system_user_and_subusers {
    my ($system_user) = @_;

    die Cpanel::Exception::create( 'MissingParameter', [ name => 'system_user' ] ) if !length $system_user;
    Cpanel::Validate::FilesystemNodeName::validate_or_die($system_user);
    Cpanel::AcctUtils::Account::accountexists_or_die($system_user);

    my $linked_users = _get_link_directory_usernames($system_user);
    my %user_links   = ();

    return \%user_links if !scalar @$linked_users;

    for my $user (@$linked_users) {
        $user_links{$user} = get_authn_links_for_user($user);
    }

    return \%user_links;
}

###########################################################################
#
# Method:
#   get_authn_link_for_user_by_provider
#
# Description:
#   This function gets the value of a specific authentication link to a remote authority.
#
# Parameters:
#   $user          - The user (cPanel user/reseller or email account) to get the links for.
#   $protocol      - The protocol used by the remote authority (such as openid_connect, or any other protocol we eventually support)
#   $provider_name - The name of the provider giving access to the specific remote authority.
#
# Exceptions:
#   Cpanel::Exception::MissingParameter - Thrown if protocol or provider_name are not passed.
#   Cpanel::Exception::InvalidParameter - Thrown if either the protocol or the provider name are not valid.
#   Anything get_authn_links_for_user can throw.
#
# Returns:
#   This method returns the identifying information that links the cPanel account to the external account or undef.
# {
#    subject_unique_identifier => Hashref of some user information (currently { preferred_username => The human readable username for the external account })
# }
#
sub get_authn_link_for_user_by_provider {
    my ( $user, $protocol, $provider_name ) = @_;

    # These will die if invalid
    Cpanel::Validate::OpenIdConnect::check_protocol_or_die($protocol);
    Cpanel::Validate::AuthProvider::check_provider_name_or_die($provider_name);

    my $authn_links = get_authn_links_for_user($user);
    if ( !$authn_links->{$protocol} || !$authn_links->{$protocol}{$provider_name} ) {
        return undef;
    }

    return $authn_links->{$protocol}{$provider_name};
}

###########################################################################
#
# Method:
#   get_users_by_authn_provider_and_link
#
# Description:
#   This function is used to lookup which cPanel user(s) is associated with the provided
#   protocol (such as openid_connect), provider (such as manage2/cpanelID), and the external account link (subject_unique_identifier)
#   NOTE: This function currently returns a list of only one user or an empty list. In the future, when we can support multiple links
#   to an external user this will change.
#
# Parameters:
#   $protocol      - The protocol used by the remote authority (such as openid_connect)
#   $provider_name - The name of the provider giving access to the specific remote authority.
#   $subject_unique_identifier - Whatever identifying information we're using to link an external account to a cPanel user
#
# Exceptions:
#   Cpanel::Exception::MissingParameter - Thrown if any of the parameters are not passed.
#   Cpanel::Exception::InvalidParameter - Thrown if any of the parameters are not valid.
#   Anything Cpanel::Security::Authn::LinkDB::get_users_by_subject_unique_identifier can throw.
#
# Returns:
#   This method should return the username(s) associated with the external account. If no link is found, return an empty list.
#   NOTE: This function is written to return a list, but currently will only return one item in that list or an empty list.
#   In the future, when we can support multiple links to an external user this will change.
#
sub get_users_by_authn_provider_and_link {
    my ( $protocol, $provider_name, $subject_unique_identifier ) = @_;

    Cpanel::Validate::OpenIdConnect::check_protocol_or_die($protocol);
    Cpanel::Validate::AuthProvider::check_provider_name_or_die($provider_name);
    Cpanel::Validate::OpenIdConnect::check_subject_unique_identifier_or_die($subject_unique_identifier);

    Cpanel::Context::must_be_list();

    require Cpanel::Security::Authn::LinkDB;
    my $linkdb = Cpanel::Security::Authn::LinkDB->new(
        'protocol'      => $protocol,
        'provider_name' => $provider_name,
    );

    return $linkdb->get_users_by_subject_unique_identifier(
        'subject_unique_identifier' => $subject_unique_identifier,
    );
}

sub _get_link_directory_usernames {
    my ($system_user) = @_;

    my $user_link_dir = get_user_db_directory($system_user);

    my $link_dbs = Cpanel::FileUtils::Dir::get_directory_nodes_if_exists($user_link_dir);

    my @usernames;
    for my $link_db (@$link_dbs) {
        next if ( length $link_db ) < 4;           # has to be more than '.db'
        next if substr( $link_db, -3 ) ne '.db';

        push @usernames, substr( $link_db, 0, ( length $link_db ) - 3 );
    }

    return \@usernames;
}

sub _get_authn_user_db_reader {
    my ($user) = @_;

    return Cpanel::Transaction::File::JSONReader->new(
        path => get_db_path($user),
    );
}

sub _get_authn_links_for_user {
    my ($user) = @_;

    my $transaction = _get_authn_user_db_reader($user);
    return get_authn_links_from_transaction($transaction);
}

sub get_authn_links_from_transaction {
    my ($transaction) = @_;

    my $data = $transaction->get_data();

    $data = {} if ref $data eq 'SCALAR' && !$$data;    # Data file uninitialized, initialze to an empty hash

    $transaction = undef;

    delete $data->{'__VERSION'};

    return $data;
}

sub get_db_path {
    my ($user) = @_;

    my $system_user = $user;
    if ( Cpanel::AcctUtils::Lookup::Webmail::is_strict_webmail_user($user) ) {
        require Cpanel::AcctUtils::Lookup;
        $system_user = Cpanel::AcctUtils::Lookup::get_system_user_without_existence_validation($user);
    }
    my $user_db_directory = get_user_db_directory($system_user);

    if ( $> == 0 && !$_CREATED_STORAGE_DIRS{$system_user} ) {
        _load_modules(qw( Cpanel::Mkdir ));
        create_storage_directories_if_missing();
        Cpanel::Mkdir::ensure_directory_existence_and_mode( $user_db_directory, $Cpanel::Security::Authn::Config::CLIENT_CONFIG_DIR_PERMS );    # PPI NO PARSE - loaded above
        $_CREATED_STORAGE_DIRS{$system_user} = 1;
    }

    my $db_file_name = get_db_file_name($user);
    return "$user_db_directory/$db_file_name";
}

sub get_db_file_name {
    my ($user) = @_;

    return "$user.db";
}

# $_[0] is a system user
sub get_user_db_directory {
    return "$Cpanel::Security::Authn::Config::AUTHN_USER_DB_DIRECTORY/$_[0]";
}

sub _load_modules {
    my (@modules) = @_;
    for my $module (@modules) {
        Cpanel::LoadModule::load_perl_module($module);
    }
    return;
}

sub create_storage_directories_if_missing {
    _load_modules(qw( Cpanel::Mkdir ));

    my $perms = $Cpanel::Security::Authn::Config::CLIENT_CONFIG_DIR_PERMS;
    my $dir   = $Cpanel::Security::Authn::Config::AUTHN_USER_DB_DIRECTORY;

    Cpanel::Mkdir::ensure_directory_existence_and_mode(    # PPI NO PARSE - loaded above
        $dir,
        $perms,
    );

    return 1;
}

1;
