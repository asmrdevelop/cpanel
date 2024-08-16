package Cpanel::Logd::BigLock;

# cpanel - Cpanel/Logd/BigLock.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use base 'Cpanel::FileGuard';
use Cpanel::BWFiles ();

sub new {
    my ($class) = @_;

    my $self = $class->SUPER::new( Cpanel::BWFiles::default_dir() );

    return $self;
}

1;
