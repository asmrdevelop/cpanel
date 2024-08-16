package Cpanel::Exception::HostingPackage::CreationError;

# cpanel - Cpanel/Exception/HostingPackage/CreationError.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Exception );

use Cpanel::LocaleString ();

#Metadata propreties:
#   package_name
#   error
sub _default_phrase {
    my ($self) = @_;

    return Cpanel::LocaleString->new(
        'The system failed to create the package “[_1]” because of an error: [_2]',
        @{ $self->{'_metadata'} }{qw(package_name error)},
    );
}

1;
