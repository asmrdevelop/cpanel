
# cpanel - Cpanel/Exception/ModSecurity/VendorUpdateUnnecessary.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Exception::ModSecurity::VendorUpdateUnnecessary;

use strict;
use warnings;

use parent 'Cpanel::Exception';

use Cpanel::LocaleString ();

sub _default_phrase {
    my ($self) = @_;
    my ( $vendor_id, $distribution ) = @{ $self->{'_metadata'} }{qw(vendor_id distribution)};
    return Cpanel::LocaleString->new( 'The update for vendor “[_1]” is unnecessary because you already have distribution “[_2]” installed.', $vendor_id, $distribution );
}

sub vendor_id {
    my ($self) = @_;
    return $self->{'_metadata'}{'vendor_id'};
}

1;
