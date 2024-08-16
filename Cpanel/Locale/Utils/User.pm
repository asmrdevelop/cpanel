package Cpanel::Locale::Utils::User;

# cpanel - Cpanel/Locale/Utils/User.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

## DO NOT ADD DEPS ##
use strict;
use Cpanel::Config::LoadCpUserFile ();
use Cpanel::Config::HasCpUserFile  ();
use Cpanel::PwCache                ();
use Cpanel::LoadModule             ();

our $DATASTORE_MODULE     = 'Cpanel::DataStore';
our $LOCALE_LEGACY_MODULE = 'Cpanel::Locale::Utils::Legacy';

my $inited_cpdata_user;
my $userlocale = {};
my $logger;

sub _logger {
    require Cpanel::Logger;
    return ( $logger ||= Cpanel::Logger->new() );
}

sub init_cpdata_keys {
    my $user = shift || $Cpanel::user || $ENV{'REMOTE_USER'} || ( $> == 0 ? 'root' : ( Cpanel::PwCache::getpwuid($>) )[0] || '' );

    return if ( defined $inited_cpdata_user && $inited_cpdata_user eq $user );

    if ( !$Cpanel::CPDATA{'LOCALE'} && $user ne 'root' ) {
        require Cpanel::Server::Utils;
        if ( Cpanel::Server::Utils::is_subprocess_of_cpsrvd() && ( $> && $user ne 'cpanel' && $user ne 'cpanellogin' && !-e "/var/cpanel/users/$user" ) ) {
            _logger()->panic("get_handle() called before initcp()");
        }

        ##
        # get_user_locale opens the cpuser file for $user In some scenarios this results in a mismatch with the process ID.
        #   templates for login form, 404 handling, and likely others, have a user=reseller and $> = cpanellogin. This is a mismatch and will result in a stace trace being logged
        #   templates served for an authenticated session have a user=reseller and $> = 0. This will succeed .
        if ( $> == 0 || ( $> && $> == ( Cpanel::PwCache::getpwnam($user) // -1 ) ) ) {
            $Cpanel::CPDATA{'LOCALE'} = get_user_locale($user);
        }
    }

    return ( $inited_cpdata_user = $user );
}

sub clear_user_cache {
    my ($user) = @_;
    return delete $userlocale->{$user};
}

sub get_user_locale {

    # '' or !defined arg or $Cpanel:User
    my $user       = ( shift || $Cpanel::user || $ENV{'REMOTE_USER'} || ( $> == 0 ? 'root' : ( Cpanel::PwCache::getpwuid($>) )[0] ) );
    my $cpuser_ref = shift;                                                                                                              # not required, just faster if it is passed
    if ( $ENV{'TEAM_USER'} ) {
        my $team_user_locale = get_team_user_locale();
        return ( $userlocale->{$user} = $team_user_locale ) if $team_user_locale;
    }

    if ( !$user ) {
        require Cpanel::Locale;
        return Cpanel::Locale::get_server_locale() || 'en';
    }

    #EXAMPLE: get_user_locale( $user, 1 ) == do not use cache && re-cache
    return $userlocale->{$user} if exists $userlocale->{$user} && !shift;

    # Only use the $Cpanel::CPDATA{'LOCALE'} key if we are loading the locale for that user
    if ( $Cpanel::user && $user eq $Cpanel::user && $Cpanel::CPDATA{'LOCALE'} ) {
        return ( $userlocale->{$user} = $Cpanel::CPDATA{'LOCALE'} );
    }

    my $locale;

    if ( $user eq 'root' ) {
        my $root_conf_yaml = ( Cpanel::PwCache::getpwnam('root') )[7] . '/.cpanel_config';
        if ( -e $root_conf_yaml ) {
            Cpanel::LoadModule::load_perl_module($DATASTORE_MODULE);
            my $hr = $DATASTORE_MODULE->can('fetch_ref')->($root_conf_yaml);
            $locale = $hr->{'locale'};
        }
    }
    elsif ( $user eq 'cpanel' ) {
        require Cpanel::Locale;
        $locale = Cpanel::Locale::get_locale_for_user_cpanel();
    }
    else {
        if ( $cpuser_ref || ( Cpanel::Config::HasCpUserFile::has_readable_cpuser_file($user) && ( $cpuser_ref = Cpanel::Config::LoadCpUserFile::loadcpuserfile($user) ) ) ) {
            if ( defined $cpuser_ref->{'LOCALE'} ) {
                $locale = $cpuser_ref->{'LOCALE'};
            }
            elsif ( defined $cpuser_ref->{'LANG'} ) {
                Cpanel::LoadModule::load_perl_module($LOCALE_LEGACY_MODULE);
                $locale = $LOCALE_LEGACY_MODULE->can('map_any_old_style_to_new_style')->( $cpuser_ref->{'LANG'} );
            }
        }
    }

    if ( !$locale ) {
        require Cpanel::Locale;
        return $userlocale->{$user} = Cpanel::Locale::get_server_locale() || 'en';
    }

    $userlocale->{$user} = $locale;

    return $userlocale->{$user};
}

sub get_team_user_locale {
    Cpanel::LoadModule::load_perl_module('Cpanel::Team::Config');
    my $locale = Cpanel::Team::Config->new( $ENV{'TEAM_OWNER'} )->load()->{users}->{ $ENV{'TEAM_USER'} }->{locale};
    return $locale;
}

1;
