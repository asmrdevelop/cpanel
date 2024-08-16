package Cpanel::DB::Prefix;

# cpanel - Cpanel/DB/Prefix.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::DB::Utils          ();
use Cpanel::DB::Prefix::Conf   ();
use Cpanel::Config::LoadCpConf ();
use Cpanel::Database           ();

our $PRE_MARIADB_TEN_PREFIX_LENGTH  = 8;
our $POST_MARIADB_TEN_PREFIX_LENGTH = 16;
our $MARIADB_TEN_MIN_VERSION        = '10.0';
our $PREFIX_LENGTH;

sub get_prefix_length {
    return $PREFIX_LENGTH if defined $PREFIX_LENGTH;

    my $cpconf = Cpanel::Config::LoadCpConf::loadcpconf();
    if ( $cpconf->{'force_short_prefix'} ) {
        return $PRE_MARIADB_TEN_PREFIX_LENGTH;
    }

    # If MySQL is not enabled we want the shortest possible length.
    # This limit affects PostgreSQL as well as MySQL.
    require Cpanel::Services::Enabled;
    if ( Cpanel::Services::Enabled::is_provided('mysql') ) {
        require Cpanel::MysqlRun;
        return ( $PREFIX_LENGTH = $PRE_MARIADB_TEN_PREFIX_LENGTH ) unless Cpanel::MysqlRun::running();

        my $db = Cpanel::Database->new();
        return ( $PREFIX_LENGTH = $db->prefix_length );
    }

    return ( $PREFIX_LENGTH = $PRE_MARIADB_TEN_PREFIX_LENGTH );
}

*use_prefix = \&Cpanel::DB::Prefix::Conf::use_prefix;

#NOTE: Unlike many other things that return a "prefix",
#this does NOT include the trailing underscore. (Sorry...)
sub username_to_prefix {
    my ($username) = @_;

    return substr(
        Cpanel::DB::Utils::username_to_dbowner($username),
        0,
        get_prefix_length(),
    );
}

#This SHOULD be reliable since only one user can have a given DB prefix on
#a given server at a time.
sub prefix_to_username {
    my ($prefix) = @_;

    my $userowners_hr = _load_user_to_owner_hashref();

    for my $user ( keys %$userowners_hr ) {
        if ( username_to_prefix($user) eq $prefix ) {
            return $user;
        }
    }

    return undef;
}

#For testing
sub _load_user_to_owner_hashref {
    require Cpanel::Config::LoadUserOwners;
    return Cpanel::Config::LoadUserOwners::loadtrueuserowners( undef, 1, 1 );
}

#NOTE: This code ALWAYS adds the DB prefix.
sub add_prefix {
    my ( $cpuser, $name ) = @_;

    return username_to_prefix($cpuser) . "_$name";
}

#NOTE: This code only prefixes if the $name doesn't already have a
#prefix. That's a less-than-ideal usage pattern that hopefully will go away,
#but as of 11.44 all database APIs behave this way.
#
sub add_prefix_if_name_needs {
    my ( $cpuser, $name ) = @_;

    my $prefix = username_to_prefix($cpuser);

    #If the given name already has the prefix, then don't re-add it.
    #That means that if user "bob" wants to create "bob_bob_db1",
    #this will need to receive $name of "bob_bob_bob_db1".
    return $name if $name =~ m<\A\Q$prefix\E_.+>;

    return "$prefix\_$name";
}

1;
