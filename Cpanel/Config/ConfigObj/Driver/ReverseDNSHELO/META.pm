package Cpanel::Config::ConfigObj::Driver::ReverseDNSHELO::META;

# cpanel - Cpanel/Config/ConfigObj/Driver/ReverseDNSHELO/META.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Autodie ();

=encoding utf-8

=head1 NAME

Cpanel::Config::ConfigObj::Driver::ReverseDNSHELO::META

=head1 DESCRIPTION

Feature Showcase metadata for ReverseDNSHELO

=cut

use parent qw(Cpanel::Config::ConfigObj::Interface::Config::Version::v1);

our $VERSION = "1.0";

=head1 FUNCTIONS

=head2 get_driver_name()

Returns the driver name. This name is used as the filename for the touchfile
put in the C</var/cpanel/activate/features/> directory.

=cut

use constant get_driver_name => 'reversednshelo';

=head2 content

Defines the content used in the Feature Showcase entry

=cut

sub content {
    my ($locale) = @_;

    my ( $short, $long, $abstract );
    if ($locale) {
        $short    = $locale->maketext('Reverse [asis,DNS] for [asis,HELO]');
        $long     = $locale->maketext('Use reverse [asis,DNS] for [output,acronym,SMTP,Simple Mail Transfer Protocol] [asis,HELO]');
        $abstract = $locale->maketext('Configure [asis,Exim] to use the sending [asis,IP] address’s reverse [asis,DNS] ([asis,PTR]) name as the [output,acronym,SMTP,Simple Mail Transfer Protocol] “[asis,HELO]”.') . ' ' . $locale->maketext('If your reverse [asis,DNS] is properly configured, this setting will help to reduce reverse DNS issues with your email deliverability.');
    }
    else {
        $short = 'Reverse DNS for HELO',
          $long = 'Use reverse DNS for SMTP HELO',
          $abstract = 'Configure Exim to use the sending IP address’s reverse DNS (PTR) name as the SMTP “HELO”.' . ' ' . 'If your reverse DNS is properly configured, this setting will help to reduce reverse DNS issues with your email deliverability.';
    }
    return {
        'vendor' => 'cPanel, LLC.',
        'url'    => 'https://go.cpanel.net/featureshowcasereversednshelo',
        'name'   => {
            'short'  => $short,
            'long'   => $long,
            'driver' => get_driver_name(),
        },
        'since'    => '11.84',
        'version'  => $Cpanel::Config::ConfigObj::Driver::ReverseDNSHELO::META::VERSION,
        'readonly' => 0,
        'abstract' => $abstract,
    };
}

=head2 showcase()

Determine how and if an item should appear in the showcase

=cut

sub showcase {
    return undef if already_enabled();
    return undef if _has_custom_mailhelo();

    return { 'is_recommended' => 1, 'is_spotlight_feature' => 1 };
}

=head2 already_enabled()

Returns true if use_rdns_for_helo is already enabled.

=cut

sub already_enabled {
    return Cpanel::Autodie::exists('/var/cpanel/use_rdns_for_helo');
}

sub _has_custom_mailhelo {
    require Whostmgr::TweakSettings;                 # PPI USE OK - accomodate next line
    Whostmgr::TweakSettings::load_module('Mail');    # PPI USE OK - Needs to be loaded before Whostmgr::TweakSettings::Configure::Mail
    require Whostmgr::TweakSettings::Configure::Mail;
    my $mail         = Whostmgr::TweakSettings::Configure::Mail->new();
    my $current_conf = $mail->get_conf();
    return 1 if $current_conf->{'custom_mailhelo'};
    return 0;
}

1;
