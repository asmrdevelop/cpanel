package Cpanel::Exception::MissingDocumentRoot;

# cpanel - Cpanel/Exception/MissingDocumentRoot.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Exception::MissingDocumentRoot

=head1 SYNOPSIS

    Cpanel::Exception::create('MissingDocumentRoot,
    'You do not have a document root for the domain “[_1]”.', [$domain] );

=head1 DESCRIPTION

This exception class is for representing when a user’s document root
is missing for a given domain.

=cut

use parent qw( Cpanel::Exception );

1;
