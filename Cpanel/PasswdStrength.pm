package Cpanel::PasswdStrength;

# cpanel - Cpanel/PasswdStrength.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::PasswdStrength::Check     ();
use Cpanel::PasswdStrength::Constants ();

use Cpanel::API ();

sub PasswdStrength_init { }

sub api2_appstrengths {
    my @RSD           = ( { 'app' => 'htaccess', 'strength' => 0 } );
    my $base_strength = Cpanel::PasswdStrength::Check::get_required_strength();
    $Cpanel::CPVAR{'minpwstrength'} = $base_strength;
    foreach my $app ( keys %Cpanel::PasswdStrength::Constants::APPNAMES ) {
        my $app_str = Cpanel::PasswdStrength::Check::get_required_strength($app);
        if ( $base_strength != $app_str ) {
            $Cpanel::CPVAR{ 'minpwstrength_' . $app } = $app_str;
            push @RSD, { 'app' => $app, 'strength' => $app_str };
        }
    }
    return \@RSD;
}

sub api2_get_password_strength {
    my (%OPTS) = @_;
    if ( !exists $OPTS{'password'} ) {
        $Cpanel::CPERROR{'passwdstrength'} = 'The password parameter was not passed';
        return;
    }
    return { 'strength' => Cpanel::PasswdStrength::Check::get_password_strength( $OPTS{'password'} ) };
}

## DEPRECATED!
sub api2_get_required_strength {
    my (%OPTS) = @_;
    my $result = Cpanel::API::_execute( "PasswdStrength", "get_required_strength", \%OPTS );
    return $result->data();
}

my $allow_demo = { allow_demo => 1 };

our %API = (
    appstrengths          => $allow_demo,
    get_password_strength => $allow_demo,
    get_required_strength => $allow_demo,
);

sub api2 {
    my ($func) = @_;
    return { %{ $API{$func} } } if $API{$func};
    return;
}

1;
