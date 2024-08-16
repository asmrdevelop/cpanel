package Cpanel::Exception::Backup::CorruptedBackupData;

# cpanel - Cpanel/Exception/Backup/CorruptedBackupData.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::Exception::Backup::CorruptedBackupData

=head1 SYNOPSIS

    Cpanel::Exception::create('Backup::CorruptedBackupData', 'There was an error while restoring the file “[_1]”.', [$file] );

=head1 DESCRIPTION

This exception class is used when we are unable to understand the data in a backup.

=cut

use strict;
use warnings;

use parent qw( Cpanel::Exception );

1;
