
# cpanel - Cpanel/cPAddons/Defaults.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::cPAddons::Defaults;

use strict;
use warnings;

use Cpanel::cPAddons::Util ();
use Cpanel::Encoder::Tiny  ();

=head1 NAME

Cpanel::cPAddons::Defaults

=head1 DESCRIPTION

Utility module that generates the defaults for cpaddon install request if the
module allow oneclick install and the request is for a oneclick install.

=head1 METHODS

=head2 Cpanel::cPAddons::Defaults::apply_defaults()

Applies the defaults to the form data if running in oneclick mode.

=head3 ARGUMENTS

=over

=item module_data | hash ref | a reference to a valid modules configuration data.

=over 10

=item module_data.meta.capabilities.install.oneclick | boolean | true if we are to provide defaults.

=item module_data.meta.adminuser_pass | boolean | true if we are to provide generated username and password.

=item module_data.meta.admin_email | boolean | true if we are to provide default email address.

=back

=item input_hr | hash ref | a reference to the form inputs

=item safe_input_hr | hash ref | a reference to the form inputs with safe encoding

=item environment | hash ref | a reference to a filled out environment hash.

=over 10

=item environment.domains.primary | string | primary domain for the account.

=item environment.contactemail | string | contact email for the account.

=back

=back

=cut

sub apply_defaults {
    my ( $module_data, $input_hr, $safe_input_hr, $environment ) = @_;

    if (   !$module_data->{meta}{capabilities}{install}{oneclick}
        || !$input_hr->{oneclick} ) {
        delete $input_hr->{oneclick};    # just in case
        return 1;
    }

    if ( $module_data->{meta}{adminuser_pass} ) {
        $input_hr->{auser}  = Cpanel::cPAddons::Util::generate_random_username();
        $input_hr->{apass}  = Cpanel::cPAddons::Util::generate_random_password();
        $input_hr->{apass2} = $input_hr->{apass};
    }

    if ( $module_data->{meta}{admin_email} ) {
        $input_hr->{contactemail} = $environment->{contactemail};
    }

    $input_hr->{subdomain}  = $input_hr->{subdomain} || $environment->{domains}{primary};
    $input_hr->{installdir} = '';

    for my $key (qw(auser apass apass2 contactemail subdomain installdir)) {
        $safe_input_hr->{$key} = Cpanel::Encoder::Tiny::safe_html_encode_str( $input_hr->{$key} );
    }

    return 1;
}

1;
