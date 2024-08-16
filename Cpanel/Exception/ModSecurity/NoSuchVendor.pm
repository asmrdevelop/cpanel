
# cpanel - Cpanel/Exception/ModSecurity/NoSuchVendor.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Exception::ModSecurity::NoSuchVendor;

use strict;
use warnings;

use parent 'Cpanel::Exception';

use Cpanel::LocaleString ();

sub _default_phrase {
    my ($self)      = @_;
    my ($vendor_id) = @{ $self->{'_metadata'} }{qw(vendor_id)};
    return Cpanel::LocaleString->new( 'The vendor “[_1]” is not set up.', $vendor_id );
}

1;
