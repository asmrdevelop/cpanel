package Cpanel::Exception::EA4PackageIsNotInstalled;

# cpanel - Cpanel/Exception/EA4PackageIsNotInstalled.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::Exception::EA4PackageIsNotInstalled

=head1 SYNOPSIS

    die Cpanel::Exception::Z<## no extract maketext>create('EA4PackageIsNotInsalled', 'ea-nginx');

=head1 DISCUSSION

This exception class means that an EA4 package that is required for the
function is not installed on this server.

=cut

use strict;
use warnings;

use parent qw( Cpanel::Exception );

use Cpanel::LocaleString ();

sub _default_phrase {
    my ($self) = @_;

    return Cpanel::LocaleString->new(
        'EA4 Package “[_1]” is required but is not installed.',
        $self->{'_metadata'}{'module'},
    );
}

1;
