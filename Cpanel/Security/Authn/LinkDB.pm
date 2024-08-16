package Cpanel::Security::Authn::LinkDB;

# cpanel - Cpanel/Security/Authn/LinkDB.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::Config::Users                 ();
use Cpanel::Context                       ();
use Cpanel::Exception                     ();
use Cpanel::LoadModule                    ();
use Cpanel::Debug                         ();
use Cpanel::Security::Authn::Config       ();
use Cpanel::Security::Authn::User         ();
use Cpanel::Transaction::File::JSON       ();
use Cpanel::Transaction::File::JSONReader ();
use Cpanel::Validate::OpenIdConnect       ();
use Cpanel::Validate::AuthProvider        ();

use Try::Tiny;

###########################################################################
#
# Method:
#   new
#
# Description:
#   This function instantiates a LinkDB object.
#
#   This module manages a directory for external authentication links to cPanel user mappings. This acts as essentially a cache.
#   The authoritative information is contained in Cpanel::Security::Authn::User
#
# Parameters:
#   protocol      - A supported external authentication protocol. See %Cpanel::Security::Authn::Config::SUPPORTED_PROTOCOLS
#   provider_name - An external authentication provider system name in lower case, such as 'cpanelid', 'google', etc.
#
# Exceptions:
#   Anything Cpanel::Validate::OpenIdConnect check_protocol and Cpanel::Validate::AuthProvider check_provider_name can throw.
#
# Returns:
#   The method returns a LinkDB object.
#
sub new {
    my ( $class, %opts ) = @_;

    my $protocol      = $opts{'protocol'};
    my $provider_name = $opts{'provider_name'};

    Cpanel::Validate::OpenIdConnect::check_protocol_or_die($protocol);
    Cpanel::Validate::AuthProvider::check_provider_name_or_die($provider_name);

    return bless {
        '_protocol'      => $protocol,
        '_provider_name' => $provider_name,
    }, $class;
}

###########################################################################
#
# Method:
#   save_links_for_user
#
# Description:
#   This function is used to sync the list of links from the authoritative source
#   which is the $Cpanel::Security::Authn::Config::AUTHN_USER_DB_DIRECTORY/$user.db file.
#
# Parameters (hash containing the following):
#   user          - The cPanel user to add/remove the links for.
#   links         - A hashref of links for the user.
#                   Adding links looks like:
#                   {
#                      'subject_unique_identifier' => {
#                           'preferred_username' => the more human readable identifying information for the external account
#                           'link_time'          => (optional) the time the link was first created, if not passed the current time will be used.
#                           NOTE: If undef is passed here instead of a hashref, it will remove the link instead. See next example.
#                      },
#                      'subject_unique_identifier2' => { 'preferred_username' => 'Bob Someone', 'link_time' => 1442871717 },
#                      'subject_unique_identifier3' => { 'preferred_username' => 'alice@somewhere.tld' },
#                   }
#                   Removing links looks like:
#                   {
#                      'subject_unique_identifier' => undef
#                   }
#
# Exceptions:
#   Cpanel::Exception::MissingParameter - Thrown if user or links are missing from the opts.
#   Cpanel::Exception::UserNotFound     - Thrown if the supplied user does not exist on the system.
#   Anything Cpanel::Transaction::File::JSON* can throw.
#
# Returns:
#   The method returns 1 on success or throws an exception if it failed.
#
sub save_links_for_user {
    my ( $self, %opts ) = @_;

    my $user  = $opts{'user'};
    my $links = $opts{'links'};

    foreach my $required_param (qw(user links)) {
        die Cpanel::Exception::create( 'MissingParameter', [ 'name' => $required_param ] ) if !length $opts{$required_param};
    }

    Cpanel::Validate::OpenIdConnect::check_user_exists_or_die($user);

    my $transaction = $self->_get_authn_link_db_transaction();
    my $data        = $transaction->get_data();
    $data = {} if ref $data ne 'HASH';    # Initialze to an empty hash

    foreach my $subject_unique_identifier ( keys %{$links} ) {
        my $user_info = $links->{$subject_unique_identifier};

        if ( $user_info && ref $user_info eq 'HASH' && keys %$user_info ) {
            $data->{'subject_unique_identifier'}{$subject_unique_identifier}{$user} = { %{$user_info}, 'version' => $Cpanel::Security::Authn::Config::VERSION };
            $data->{'user'}{$user}{$subject_unique_identifier}                      = 1;
        }
        else {
            delete $data->{'subject_unique_identifier'}{$subject_unique_identifier}{$user};
            delete $data->{'subject_unique_identifier'}{$subject_unique_identifier} if !scalar keys %{ $data->{'subject_unique_identifier'}{$subject_unique_identifier} };
            delete $data->{'user'}{$user}{$subject_unique_identifier};
            delete $data->{'user'}{$user} if !scalar keys %{ $data->{'user'}{$user} };
        }
    }

    $transaction->set_data($data);
    $transaction->save_and_close_or_die();

    return 1;
}

###########################################################################
#
# Method:
#   get_links_for_users_matching_regex
#
# Description:
#   This function is used to lookup all the links for a list of users
#
# Parameters:
#   regex - A regular expression that matches only the users needed
#
# Exceptions:
#   Anything Cpanel::Transaction::File::JSON* can throw.
#
# Returns:
#   A hashref of LinkDB entries indexed by username
#   and subject_unique_identifier
#
sub get_links_for_users_matching_regex {
    my ( $self, %opts ) = @_;

    my $regex = $opts{'regex'} or die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'regex' ] );
    if ( $regex eq qr{} || $regex eq qr{}u ) { die Cpanel::Exception::create( 'InvalidParameter', "“[_1]” may not be an empty regular expression.", ['regex'] ); }

    my $reader_transaction = $self->_get_authn_link_db_reader();
    my $data               = $reader_transaction->get_data();

    # Return no users if the LinkDB hasn't been initialized
    return {} if ref $data eq 'SCALAR' && !$$data;

    my %links;

    foreach my $user ( grep( m{$regex}, keys %{ $data->{'user'} } ) ) {
        foreach my $subject_unique_identifier ( keys %{ $data->{'user'}{$user} } ) {
            $links{$user}{$subject_unique_identifier} = $data->{'subject_unique_identifier'}{$subject_unique_identifier}{$user};
        }
    }

    return \%links;
}

###########################################################################
#
#   remove_all_links_for_users
#
# Description:
#   This function is used to mass delete user links from the link db. This is used when removing a system user and all its subusers.
#
# Parameters (hash containing the following):
#   users          - An arrayref of usernames to remove links for.
#
# Exceptions:
#   Cpanel::Exception::MissingParameter - Thrown if users is missing from $opts
#   Cpanel::Exception::UserNotFound     - Thrown if one of the supplied users does not exist on the system.
#   Cpanel::Exception::Collection       - A collection of exceptions that were encountered during execution.
#                                         This may contain exceptions about closing or saving the link db, but
#                                         it will usually contain mostly UserNotFound exceptions.
#   Anything Cpanel::Transaction::File::JSON* can throw.
#
# Returns:
#   The method returns 1 on success or throws an exception if it failed.
#
sub remove_all_links_for_users {
    my ( $self, %opts ) = @_;

    my $users = $opts{'users'};

    die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'users' ] ) if !$users;

    my $transaction = $self->_get_authn_link_db_transaction();
    my $data        = $transaction->get_data();
    return 1 if ref $data ne 'HASH';    # If the datastore is empty we have nothing to remove.

    my @exceptions;
    my $err;
    for my $user (@$users) {
        try {
            Cpanel::Validate::OpenIdConnect::check_user_exists_or_die($user);
        }
        catch {
            $err = $_;
        };

        if ($err) {
            push @exceptions, $err;
            next;
        }

        my $user_sub_ids = delete $data->{'user'}{$user};
        if ( $user_sub_ids && keys %$user_sub_ids ) {
            for my $sub_id ( keys %$user_sub_ids ) {
                delete $data->{'subject_unique_identifier'}{$sub_id}{$user};
                delete $data->{'subject_unique_identifier'}{$sub_id} if !scalar keys %{ $data->{'subject_unique_identifier'}{$sub_id} };
            }
        }
    }

    try {
        $transaction->set_data($data);
        $transaction->save_and_close_or_die();
    }
    catch {
        push @exceptions, $_;
    };

    if (@exceptions) {
        die Cpanel::Exception::create( 'Collection', 'The system encountered the following [numerate,_1,error,errors] while it tried to remove the link data for [list_and_quoted,_2].', [ scalar @exceptions, $users ], { exceptions => \@exceptions } );
    }

    return 1;
}

###########################################################################
#
# Method:
#   get_users_by_subject_unique_identifier
#
# Description:
#   This function is used to lookup which cPanel user is associated with the provided
#   protocol (such as openid_connect), provider (such as manage2), and the external account link
#   Note: Must be called in list context as this returns a list for future expansion. Eventually, we'll
#   be able to link multiple cPanel account to one external account, but that currently is not the case.
#
# Parameters:
#   subject_unique_identifier - Whatever identifying information we're using to link an external account to a cPanel user
#
# Exceptions:
#   Anything Cpanel::Validate::OpenIdConnect::check_subject_unique_identifier_or_die throws.
#   Anything Cpanel::Transaction::File::JSON* can throw.
#
# Returns:
#   This method should return the username associated with the external account. If no link is found, return nothing.
#   Note: The username is returned as a single item in a list to support the future ability to link multiple cPanel
#   accounts to a single external account.
#
sub get_users_by_subject_unique_identifier {
    my ( $self, %opts ) = @_;

    Cpanel::Context::must_be_list();

    my $subject_unique_identifier = $opts{'subject_unique_identifier'};

    Cpanel::Validate::OpenIdConnect::check_subject_unique_identifier_or_die($subject_unique_identifier);

    my $reader_transaction = $self->_get_authn_link_db_reader();
    my $data               = $reader_transaction->get_data();

    # Return no users if the LinkDB hasn't been initialized
    return () if ref $data eq 'SCALAR' && !$$data;

    return keys %{ $data->{'subject_unique_identifier'}{$subject_unique_identifier} };
}

###########################################################################
#
# Method:
#   rebuild
#
# Description:
#   This function is used to rebuild the links database for a provider
#   from the $Cpanel::Security::Authn::Config::AUTHN_USER_DB_DIRECTORY/$user/*.db files.
#
# Parameters:
#   none
#
# Exceptions:
#   Anything Cpanel::Transaction::File::JSON* can throw.
#   Anything Cpanel::Security::Authn::User::get_authn_links_for_user can throw.
#
# Returns:
#   The method returns 1 on success or throws an exception if it failed.
#
sub rebuild {
    my ($self) = @_;

    my $users_arr_ref = Cpanel::Config::Users::getcpusers();

    my $transaction = $self->_get_authn_link_db_transaction();
    my $data        = $transaction->get_data();
    $data = {} if ref $data ne 'HASH';

    delete $data->{'user'};
    delete $data->{'subject_unique_identifier'};

    foreach my $system_user (@$users_arr_ref) {
        $self->_rebuild_system_user_data( $system_user, $data );
    }

    $transaction->set_data($data);
    $transaction->save_and_close_or_die();
    return 1;
}

###########################################################################
#
# Method:
#   change_usernames
#
# Description:
#   This function is used to mass change the usernames and resulting link cache information
#   for authentication users.
#
# Parameters (a hashref with the following keys):
#   username_map => A hashref mapping of current usernames to new usernames.
#                   {
#                      currentuser    => newuser,
#                      auser@blah.tld => auser@anotherdomain.tld,
#                   }
#
# Exceptions:
#   Anything Cpanel::Transaction::File::JSON* can throw.
#
# Returns:
#   The method returns 1 on success or throws an exception if it failed.
#
sub change_usernames {
    my ( $self, %opts ) = @_;

    my $username_map = $opts{'username_map'};

    my $transaction = $self->_get_authn_link_db_transaction();
    my $data        = $transaction->get_data();

    return 1 if ref $data ne 'HASH';    # No need to change the username if the link DB wasn't initialized

    for my $old_username ( keys %$username_map ) {
        next if !$data->{'user'}{$old_username};
        my $new_username = $username_map->{$old_username};

        $data->{'user'}{$new_username} = delete $data->{'user'}{$old_username};
        for my $sub_id ( keys %{ $data->{'user'}{$new_username} } ) {
            $data->{'subject_unique_identifier'}{$sub_id}{$new_username} = delete $data->{'subject_unique_identifier'}{$sub_id}{$old_username};
        }
    }

    $transaction->set_data($data);
    $transaction->save_and_close_or_die();

    return 1;
}

sub _rebuild_system_user_data {
    my ( $self, $system_user, $data ) = @_;

    my $protocol      = $self->_protocol();
    my $provider_name = $self->_provider_name();

    my @link_users = Cpanel::Security::Authn::User::get_all_link_enabled_users_for_system_user($system_user);
    for my $link_user (@link_users) {
        my $links = try {
            Cpanel::Security::Authn::User::get_authn_links_for_user($link_user);
        }
        catch {
            Cpanel::Debug::log_warn( "The system was unable to get external authentication links for '$link_user': " . Cpanel::Exception::get_string($_) );
        };

        next if !$links              || !ref $links;
        next if !$links->{$protocol} || !$links->{$protocol}{$provider_name};

        foreach my $subject_unique_identifier ( keys %{ $links->{$protocol}{$provider_name} } ) {
            my $user_info = $links->{$protocol}{$provider_name}{$subject_unique_identifier};
            $data->{'subject_unique_identifier'}{$subject_unique_identifier}{$link_user} = { %{$user_info}, 'version' => $Cpanel::Security::Authn::Config::VERSION };
            $data->{'user'}{$link_user}{$subject_unique_identifier}                      = 1;
        }
    }

    return 1;
}

sub _provider_name {
    my ($self) = @_;
    return $self->{'_provider_name'};
}

sub _protocol {
    my ($self) = @_;
    return $self->{'_protocol'};
}

sub _get_authn_link_db_transaction {
    my ($self) = @_;

    return Cpanel::Transaction::File::JSON->new( path => $self->_get_db_path(), permissions => 0600 );
}

sub _get_authn_link_db_reader {
    my ($self) = @_;

    return Cpanel::Transaction::File::JSONReader->new( path => $self->_get_db_path(), permissions => 0600 );
}

sub _get_db_path {
    my ($self)        = @_;
    my $protocol      = $self->_protocol();
    my $provider_name = $self->_provider_name();

    # These will die if invalid
    Cpanel::Validate::OpenIdConnect::check_protocol_or_die($protocol);
    Cpanel::Validate::AuthProvider::check_provider_name_or_die($provider_name);

    create_storage_directories_if_missing($protocol) if $> == 0;

    return __login_directory_for_protocol($protocol) . "/$provider_name.db";

}

sub create_storage_directories_if_missing {
    my ($protocol) = @_;

    Cpanel::LoadModule::load_perl_module('Cpanel::Mkdir');

    Cpanel::Mkdir::ensure_directory_existence_and_mode(
        $Cpanel::Security::Authn::Config::AUTHN_LINK_DB_DIRECTORY_BASE,
        $Cpanel::Security::Authn::Config::CLIENT_CONFIG_DIR_PERMS,
    );

    my $PROTOCOL_DIR = "$Cpanel::Security::Authn::Config::AUTHN_LINK_DB_DIRECTORY_BASE/$protocol";
    Cpanel::Mkdir::ensure_directory_existence_and_mode(
        $PROTOCOL_DIR,
        $Cpanel::Security::Authn::Config::LOGIN_DB_DIR_PERMS,
    );

    my $PROTOCOL_LOGIN_DIR = __login_directory_for_protocol($protocol);
    Cpanel::Mkdir::ensure_directory_existence_and_mode(
        $PROTOCOL_LOGIN_DIR,
        $Cpanel::Security::Authn::Config::LOGIN_DB_DIR_PERMS,
    );

    return 1;
}

sub __login_directory_for_protocol {
    my ($protocol) = @_;

    return "$Cpanel::Security::Authn::Config::AUTHN_LINK_DB_DIRECTORY_BASE/$protocol/login";
}

1;
