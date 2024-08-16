package Cpanel::Security::Policy::PasswordStrength;

# cpanel - Cpanel/Security/Policy/PasswordStrength.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#use strict;

use Cpanel::PasswdStrength::Check ();
use Cpanel::Locale::Lazy 'lh';

my $locale;

use base 'Cpanel::SecurityPolicy::Base';

sub new {
    my ($class) = @_;

    # Compiler does not necessarily properly load the base class.
    unless ( exists $INC{'Cpanel/SecurityPolicy/Base.pm'} ) {
        eval 'require Cpanel::SecurityPolicy::Base;';
    }
    return Cpanel::SecurityPolicy::Base->init( __PACKAGE__, 9997 );
}

sub fails {
    my ( $self, $sec_ctxt ) = @_;

    if ( $sec_ctxt->{'auth_by_accesshash'} || $sec_ctxt->{'auth_by_openid_connect'} ) {
        return 0;
    }

    my $required_strength = Cpanel::PasswdStrength::Check::get_required_strength( ( $sec_ctxt->{'virtualuser'} && !$sec_ctxt->{'is_possessed'} ) ? 'pop' : 'passwd' );
    if ( $sec_ctxt->{'pwstrength'} && $required_strength > $sec_ctxt->{'pwstrength'} ) {
        return 1;
    }
    return 0;
}

sub bypass_page {
    my ( $self, $sec_ctxt ) = @_;

    return $sec_ctxt->{'document'} =~ m{^\./frontend/[^/]+/passwd/(?:index|changepass)\.html}
      || $sec_ctxt->{'document'}   =~ m{^\./backend/passwordstrength\.cgi};
}

sub description {
    return lh()->maketext('Password Strength');
}

1;
