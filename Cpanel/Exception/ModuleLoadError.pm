package Cpanel::Exception::ModuleLoadError;

# cpanel - Cpanel/Exception/ModuleLoadError.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Exception );

use Cpanel::LocaleString ();

#Params:
#   module
#   error
sub _default_phrase {
    my ($self) = @_;

    return Cpanel::LocaleString->new(
        'The system failed to load the module “[_1]” because of an error: [_2]',
        @{ $self->{'_metadata'} }{qw(module error)},
    );
}

sub is_not_found {
    my ($self) = @_;

    my $err  = $self->get('error');
    my $path = $self->get('module');

    $path =~ s<::></>g;
    $path .= '.pm';

    return ( 0 == index( $err, "Can't locate $path" ) );
}

1;
