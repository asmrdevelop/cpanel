package Cpanel::ServiceConfig::cpsrvd;

# cpanel - Cpanel/ServiceConfig/cpsrvd.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

our $VERSION = '1.2';

use strict;

use Cpanel::Locale ('lh');

use parent 'Cpanel::ServiceConfig::cPanel';

sub new {
    my $class = shift;
    my $self  = $class->SUPER::new();
    $self->{'display_name'}   = lh()->maketext('[asis,cPanel] Web Services');
    $self->{'type'}           = 'cpsrvd';
    $self->{'datastore_name'} = 'cpsrvd';

    return $self;
}

1;
