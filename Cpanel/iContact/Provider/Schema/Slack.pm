package Cpanel::iContact::Provider::Schema::Slack;

# cpanel - Cpanel/iContact/Provider/Schema/Slack.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::LoadModule ();

# Name is always uc(MODULE)

=encoding utf-8

=head1 NAME

Cpanel::iContact::Provider::Schema::Slack - Schema for the Slack iContact module

=head1 SYNOPSIS

    use Cpanel::iContact::Provider::Schema::Slack;

    my $settings = Cpanel::iContact::Provider::Schema::Slack::get_settings();

    my $config = Cpanel::iContact::Provider::Schema::Slack::get_config();


=head1 DESCRIPTION

Provide settings and configuration for the Slack iContact module.

=head2 get_settings

Provide config data for TweakSettings that will be saved in
/etc/wwwacct.conf.shadow

=head3 Input

None

=head3 Output

A hashref that can be injected into Whostmgr::TweakSettings::Basic's %Conf
with the additional help and label keys that are used in the display of the
tweak settings.

=cut

sub get_settings {
    return {
        'CONTACTSLACK' => {
            'shadow'   => 1,
            'type'     => 'text',
            'checkval' => sub {
                Cpanel::LoadModule::load_perl_module('Cpanel::StringFunc::Trim');
                my $value = shift();
                $value = Cpanel::StringFunc::Trim::ws_trim($value);

                return $value if $value eq q{};

                my @urls = split m{\s*,\s*}, $value;

                return join( ',', grep ( m{^https?://}, @urls ) );
            },
            'label' => 'Slack WebHook',
            'help'  => 'Slack WebHook URL. Multiple hooks can be specified by separating with a comma(,). To obtain your own Slack WebHook, please follow the guide at https://api.slack.com/messaging/webhooks',
        }
    };
}

=head2 get_config

Obtain configuration for the module.

=head3 Input

None

=head3 Output

A hash ref containing the following key values:

  default_level:    The iContact default contact level (All)
  display_name:     The name displayed on the Contact Manager page in WHM.
  verification_api: The api used to verify settings provided by the user for this module (not currently pluggable)

=cut

sub get_config {
    return {
        'default_level'    => 'All',
        'display_name'     => 'Slack',
        'verification_api' => 'verify_slack_access',    # Currently not possible to dynamically create
    };
}

1;
