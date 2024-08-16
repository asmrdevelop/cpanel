package Cpanel::iContact::Provider::Schema::Posturl;

# cpanel - Cpanel/iContact/Provider/Schema/Posturl.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::LoadModule ();

# Name is always uc(MODULE)

=encoding utf-8

=head1 NAME

Cpanel::iContact::Provider::Schema::Posturl - Schema for the Posturl iContact module

=head1 SYNOPSIS

    use Cpanel::iContact::Provider::Schema::Posturl;

    my $settings = Cpanel::iContact::Provider::Schema::Posturl::get_settings();

    my $config = Cpanel::iContact::Provider::Schema::Posturl::get_config();


=head1 DESCRIPTION

Provide settings and configuration for the Posturl iContact module.

=cut

=head2 get_settings

Provide config data for TweakSettings that will be saved in
/etc/wwwacct.conf

=head3 Input

None

=head3 Output

A hashref that can be injected into Whostmgr::TweakSettings::Basic's %Conf
with the additional help and label keys that are used in the display of the
tweak settings.

=cut

sub get_settings {
    return {
        'CONTACTPOSTURL' => {
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
            'label' => 'URL(s) to POST notifications',
            'help'  =>
              'A comma-separated list of http:// or https:// URLs of a system to which you want to send POST notifications as form data with the keys "hostname", "subject", and "body". Query strings will be converted and sent as POST data. For example https://www.cpanel.net/events.cgi?apikey=XXXXX will send apikey via POST. Note that all keys and values must be in URLencoded format. Also, if you use the https://user:password@domain.tld/ format to authenticate to the destination system, you must also URLencode the "user" and "password" keys and values.'

        }
    };

}

=head2 get_config

Provide configuration for the module.

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
        'display_name'     => 'Post to a URL',
        'verification_api' => 'verify_posturl_access',    # Currently not possible to dynamically create
    };
}

1;
