package Cpanel::Security::Policy::PasswordAge;

# cpanel - Cpanel/Security/Policy/PasswordAge.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#use strict;

use Cpanel::Locale::Lazy 'lh';

my $locale;

use base 'Cpanel::SecurityPolicy::Base';

sub new {
    my ($class) = @_;

    # Compiler does not necessarily properly load the base class.
    unless ( exists $INC{'Cpanel/SecurityPolicy/Base.pm'} ) {
        eval 'require Cpanel::SecurityPolicy::Base;';
    }
    return Cpanel::SecurityPolicy::Base->init( __PACKAGE__, 9998 );
}

sub fails {
    my ( $self, $sec_ctxt, $cpconf ) = @_;

    if ( !$self->conf_value( $cpconf, 'maxage' ) ) {
        return 0;
    }
    elsif ( $sec_ctxt->{'auth_by_accesshash'} || $sec_ctxt->{'auth_by_openid_connect'} ) {
        return 0;
    }

    my $mytime           = int( time / ( 60 * 60 * 24 ) );
    my $pass_change_time = ( $sec_ctxt->{'is_possessed'} ? $sec_ctxt->{'possessor_pass_change_time'} : $sec_ctxt->{'pass_change_time'} );
    if ($pass_change_time) {
        my $days_since_change = ( $mytime - $pass_change_time );

        if ( $self->conf_value( $cpconf, 'maxage' ) < $days_since_change ) {
            return 1;
        }
        else {
            return 0;
        }

    }
    return 0;
}

sub bypass_page {
    my ( $self, $sec_ctxt ) = @_;

    return $sec_ctxt->{'document'} =~ m{^\./frontend/[^/]+/passwd/(?:index|changepass)\.html}
      || $sec_ctxt->{'document'}   =~ m{^\./backend/passwordstrength\.cgi};
}

sub description {
    return lh()->maketext('Password Age');
}

1;
