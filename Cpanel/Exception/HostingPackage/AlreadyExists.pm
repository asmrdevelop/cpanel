package Cpanel::Exception::HostingPackage::AlreadyExists;

# cpanel - Cpanel/Exception/HostingPackage/AlreadyExists.pm
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
sub _default_phrase {
    my ($self) = @_;

    return Cpanel::LocaleString->new(
        'The package “[_1]” already exists.',
        @{ $self->{'_metadata'} }{qw(package_name)},
    );
}

1;
