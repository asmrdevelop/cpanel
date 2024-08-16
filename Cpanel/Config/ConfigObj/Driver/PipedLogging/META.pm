package Cpanel::Config::ConfigObj::Driver::PipedLogging::META;

# cpanel - Cpanel/Config/ConfigObj/Driver/PipedLogging/META.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Config::ConfigObj::Driver::PipedLogging::META

=head1 DESCRIPTION

Feature Showcase metadata for PipedLogging

=cut

use parent qw(Cpanel::Config::ConfigObj::Interface::Config::Version::v1);

our $VERSION = "1.0";

=head1 FUNCTIONS

=head2 get_driver_name()

Returns the driver name. This name is used as the filename for the touchfile
put in the C</var/cpanel/activate/features/> directory.

=cut

use constant get_driver_name => 'piped_logging';

=head2 content

Defines the content used in the Feature Showcase entry

=cut

sub content {
    my ($locale) = @_;

    my ( $short, $long, $abstract );
    if ($locale) {
        $short    = $locale->maketext('Piped Logging');
        $long     = $locale->maketext('Enable Piped Logging for [asis,Apache]');
        $abstract = $locale->maketext(
            'Configure [asis,Apache] to use a single log target for all virtual host access and bandwidth logs. The combined logs will be piped to a helper application where they can be split based upon domain. This option will reduce the number of log files [asis,Apache] manages, which will free system resources. Piped logging is recommended for systems with a large number of domains. This feature defaults to enabled. If you disable this feature, [asis,Apache] will create distinct log files for each virtual host entry.'
        );
    }
    else {
        $short = 'Piped Logging';
        $long  = 'Enable Piped Logging For Apache';
        $abstract =
          'Configure [asis,Apache] to use a single log target for all virtual host access and bandwidth logs. The combined logs will be piped to a helper application where they can be split based upon domain. This option will reduce the number of log files [asis,Apache] manages, which will free system resources. Piped logging is recommended for systems with a large number of domains. This feature defaults to enabled. If you disable this feature, [asis,Apache] will create distinct log files for each virtual host entry.';
    }

    return {
        'vendor' => 'cPanel, Inc.',
        'url'    => 'https://go.cpanel.net/featureshowcasepipedlogging',
        'name'   => {
            'short'  => $short,
            'long'   => $long,
            'driver' => get_driver_name(),
        },
        'since'    => '11.74',
        'version'  => $Cpanel::Config::ConfigObj::Driver::PipedLogging::META::VERSION,
        'readonly' => 0,
        'abstract' => $abstract,
    };
}

=head2 showcase()

Determine how and if an item should appear in the showcase

=cut

sub showcase {
    return undef if already_enabled();

    #  If check() is false we should not get here because
    #  they already have a market provider enabled or the
    #  partner has disabled the cPStore market provider
    return { 'is_recommended' => 0, 'is_spotlight_feature' => 0 };
}

=head2 already_enabled()

Returns true if Piped Logging is already enabled.

=cut

sub already_enabled {
    require Whostmgr::TweakSettings;
    return Whostmgr::TweakSettings::get_value( 'Main', 'enable_piped_logs' );
}

1;
