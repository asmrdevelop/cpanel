package Cpanel::AdvConfig::cpanel_php_fpm;

# cpanel - Cpanel/AdvConfig/cpanel_php_fpm.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(RequireUseWarnings) # No idea why it doesn't use warnings, but I'm gonna assume there was a good reason

use Cpanel::AdvConfig          ();
use Cpanel::CPAN::Hash::Merge  ();
use Cpanel::ConfigFiles        ();
use Cpanel::Exception          ();
use Cpanel::Config::LoadCpConf ();

my $service = 'cpanel_php_fpm';

# Defaults
my $tz;
my $conf_defaults = {
    'user' => {
        'pm'                   => 'ondemand',
        'process_idle_timeout' => 15,
        'max_children'         => 25,
    },
    'cpanel' => {
        'pm'                   => 'ondemand',
        'process_idle_timeout' => 15,
        'max_children'         => 200,
    },
};

my $conf;

sub get_config {
    my $args_ref = shift;

    # There's caching going on all over the place, so reset every global
    if ( exists $args_ref->{'reload'} && $args_ref->{'reload'} ) {
        $conf = {};
    }

    foreach my $required (qw(user homedir type)) {
        die Cpanel::Exception::create( 'MissingParameter', [ name => $required ] ) if !$args_ref->{'opts'}{$required};
        $conf->{$required} = $args_ref->{'opts'}{$required};
    }

    if ( $conf->{'type'} ne 'cpanel' && $conf->{'type'} ne 'user' ) {
        die Cpanel::Exception::create( 'InvalidParameter', "“[_1]” is not a valid value for “[_2]”.", [ $conf->{'type'}, 'type' ] );
    }

    if ( $conf->{'_initialized'} ) {
        return wantarray ? ( 1, $conf ) : $conf;
    }

    # Find the TZ we need
    require Cpanel::Timezones;
    $tz ||= Cpanel::Timezones::get_current_timezone();
    foreach ( keys(%$conf_defaults) ) {
        $conf_defaults->{$_}->{'tz'} = $tz;
    }

    my $cpconf = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();

    if ( $cpconf->{'maxcpsrvdconnections'} > $conf_defaults->{'cpanel'}{'max_children'} ) {
        $conf_defaults->{'cpanel'}{'max_children'} = $cpconf->{'maxcpsrvdconnections'};
    }

    $conf = Cpanel::CPAN::Hash::Merge::merge( $conf, $conf_defaults->{ $conf->{'type'} } );

    my $local_conf = Cpanel::AdvConfig::load_app_conf($service);
    if ( $local_conf && ref $local_conf eq 'HASH' ) {    # Had local configuration
        $conf = Cpanel::CPAN::Hash::Merge::merge( $local_conf, $conf );
    }

    $conf->{'_target_conf_file'} = "$Cpanel::ConfigFiles::FPM_CONFIG_ROOT/$conf->{'user'}.conf";

    # TODO: In the future we will support modifing the templates and editing per cP User.
    # For now we are just allowing this for the WHM Pool users (cpanel_* like pools) as (so far),
    # they are the only ones who need it to implement CPANEL-13518.
    # This was not implemented for the 'user' type (read: cP User) for two reasons:
    #  1) There's no point in having a custom file, since all users will need max_input_vars of 10000
    #     in order for PHPMyAdmin to "work" in the way customers desire it to.
    #  2) If there were a lot of users on the system, checking for all those overrides will be wasteful,
    #     especially since there's no compelling reason *to* do it.
    #     If customers eventually desire to install custom pool configs for their users on the
    #     *cpservice* level, this would make sense.
    #     For now, since most users just turn off cpanel_php_fpm, I doubt we'll want it for a while.
    $conf->{'template_file'} = "/usr/local/cpanel/src/templates/$service/$conf->{'type'}.default";
    if ( $conf->{'type'} eq 'cpanel' && -e "/usr/local/cpanel/src/templates/$service/$conf->{'user'}.default" ) {
        $conf->{'template_file'} = "/usr/local/cpanel/src/templates/$service/$conf->{'user'}.default";
    }

    return wantarray ? ( 1, $conf ) : $conf;
}

1;
