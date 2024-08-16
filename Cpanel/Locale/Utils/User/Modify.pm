package Cpanel::Locale::Utils::User::Modify;

# cpanel - Cpanel/Locale/Utils/User/Modify.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

## DO NOT ADD DEPS ##

use strict;
use warnings;

use Cpanel::PwCache ();

sub save_user_locale {
    my ( $locale, undef, $user ) = @_;
    $locale ||= 'en';
    $user   ||= $Cpanel::user || $ENV{'REMOTE_USER'} || ( $> == 0 ? 'root' : ( Cpanel::PwCache::getpwuid_noshadow($>) )[0] );

    if ( $user eq 'root' ) {
        require Cpanel::LoadModule;

        # We avoid require here because we do not want this in
        # updatenow.static
        Cpanel::LoadModule::load_perl_module('Cpanel::DataStore');

        my $root_conf_yaml = Cpanel::PwCache::gethomedir('root') . '/.cpanel_config';
        my $hr             = Cpanel::DataStore::fetch_ref($root_conf_yaml);

        # don't update if it is the current one, use a differet RC in case this condition matters to caller
        return 2 if exists $hr->{'locale'} && $hr->{'locale'} eq $locale;

        $hr->{'locale'} = $locale;

        return 1 if Cpanel::DataStore::store_ref( $root_conf_yaml, $hr );
        return;
    }
    elsif ( $> == 0 ) {
        require Cpanel::Config::CpUserGuard;
        my $cpuser_guard = Cpanel::Config::CpUserGuard->new($user) or return;
        $cpuser_guard->{'data'}->{'LOCALE'} = $locale;
        delete $cpuser_guard->{'data'}->{'LANG'};
        delete $cpuser_guard->{'data'}{'__LOCALE_MISSING'};
        return $cpuser_guard->save();
    }
    else {
        require Cpanel::LoadModule;

        # We avoid require here because we do not want this in
        # updatenow.static
        Cpanel::LoadModule::load_perl_module('Cpanel::AdminBin');
        if ( $ENV{'TEAM_USER'} ) {
            Cpanel::LoadModule::load_perl_module('Cpanel::AdminBin::Call');
            return Cpanel::AdminBin::Call::call( 'Cpanel', 'teamconfig', 'SET_LOCALE', $ENV{'TEAM_USER'}, $locale );
        }
        return Cpanel::AdminBin::run_adminbin_with_status( 'lang', 'SAVEUSERSETTINGS', $locale, 0, $user )->{'status'};
    }
    return 1;
}

1;
