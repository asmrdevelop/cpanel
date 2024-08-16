package Cpanel::Exception::Backup::RestoreFailed;

# cpanel - Cpanel/Exception/Backup/RestoreFailed.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::Exception::Backup::RestoreFailed

=head1 SYNOPSIS

    Cpanel::Exception::create('Backup::RestoreFailed', 'There was an error while restoring the file “[_1]”.', [$file] );

=head1 DESCRIPTION

This exception class is for representing when the restoration of a file or directory fails

=cut

use strict;
use warnings;

use parent qw( Cpanel::Exception );

1;
