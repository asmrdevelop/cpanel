package Cpanel::Exception::PasswordIsTooWeak;

# cpanel - Cpanel/Exception/PasswordIsTooWeak.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Exception );

use Cpanel::LocaleString              ();
use Cpanel::PasswdStrength::Constants ();
use Cpanel::PasswdStrength::Check     ();

#Metadata propreties:
#   application - the application whose minimum strength check failed
#
sub _default_phrase {
    my ($self) = @_;

    my $required_strength = Cpanel::PasswdStrength::Check::get_required_strength( $self->get('application') );
    my $phrase;
    if ( $required_strength == Cpanel::PasswdStrength::Check::MAX_STRENGTH() ) {
        $phrase = Cpanel::LocaleString->new('The given password is too weak. Please enter a password with a strength rating of [numf,_1].');
    }
    else {
        $phrase = Cpanel::LocaleString->new('The given password is too weak. Please enter a password with a strength rating of [numf,_1] or higher.');
    }

    return $phrase->clone_with_args(
        $required_strength,
    );
}

1;
