package Cpanel::Config::LoadUserOwners;

# cpanel - Cpanel/Config/LoadUserOwners.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Cpanel::Config::LoadConfig ();

$Cpanel::Config::LoadUserOwners::VERSION = '1.0';

#A global so this can be overridden and tested.
our $TRUE_USER_OWNERS_FILE = '/etc/trueuserowners';

our $REVERSE = 1;
our $SIMPLE  = 1;

# NB: With no args this returns a hashref with the keys as the owners
# and the values as arrayrefs of the users owned by them as the values.
sub loadtrueuserowners {
    my $conf_ref = shift;
    my $reverse  = shift;
    my $simple   = shift;

    $conf_ref = Cpanel::Config::LoadConfig::loadConfig(
        $TRUE_USER_OWNERS_FILE,
        $conf_ref,
        '\s*[:]\s*',
        undef,    #use default comment
        0,        #do not pretreat lines
        0,        #do not allow undef values
        {
            'use_reverse'          => $reverse ? 0 : 1,
            'use_hash_of_arr_refs' => $simple  ? 0 : 1,
        }
    );
    if ( !defined($conf_ref) ) {
        $conf_ref = {};
    }
    return wantarray ? %{$conf_ref} : $conf_ref;
}

1;
