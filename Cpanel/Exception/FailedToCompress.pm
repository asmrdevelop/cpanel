package Cpanel::Exception::FailedToCompress;

# cpanel - Cpanel/Exception/FailedToCompress.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Exception );

=encoding utf-8

=head1 NAME

Cpanel::Exception::FailedToCompress

=head1 SYNOPSIS

    Cpanel::Exception::create('FailedToCompress', 'There was an error while restoring the file “[_1]”.', [$file] );

=head1 DESCRIPTION

This exception class is for representing when we are unable to compress a file.

=cut

1;
