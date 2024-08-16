package Cpanel::Exception::CorruptFile;

# cpanel - Cpanel/Exception/CorruptFile.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Exception::CorruptFile - “Given file is nonsense.”

=head1 SYNOPSIS

    die Cpanel::Exception::create('CorruptFile', 'Data file “[_1]” is bad.', [ $file ] );

=head1 DESCRIPTION

This class represents a rejection of a given file.  It provides
no default message.

This class extends L<Cpanel::Exception>.

=cut

#----------------------------------------------------------------------

use parent qw( Cpanel::Exception );

1;
