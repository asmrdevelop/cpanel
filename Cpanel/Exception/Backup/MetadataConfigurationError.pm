package Cpanel::Exception::Backup::MetadataConfigurationError;

# cpanel - Cpanel/Exception/Backup/MetadataConfigurationError.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::Exception::Backup::MetadataConfigurationError

=head1 SYNOPSIS

    Cpanel::Exception::create('Backup::MetadataConfigurationError', 'There was an error while restoring the file “[_1]”.', [$file] );

=head1 DESCRIPTION

This exception class is for representing when the backup system cannot create the meta data file.

=cut

use strict;
use warnings;

use parent qw( Cpanel::Exception );

1;
