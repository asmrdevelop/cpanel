package Cpanel::Output::Formatted::Plain;

# cpanel - Cpanel/Output/Formatted/Plain.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::Output::Formatted::Plain - plain-text formatted output

=head1 DESCRIPTION

This module facilitates plaintext output. It is appropriate for outputting
to log files.

=cut

use strict;

our $VERSION = '1.0';

use parent 'Cpanel::Output::Formatted';

our $product_dir = '/var/cpanel';

use constant _new_line => "\n";

sub _indent {
    return $_[0]->{'_indent_level'} ? ( "\t" x $_[0]->{'_indent_level'} ) : '';
}

sub _format_text {

    #my ( $self, undef, $text ) = @_;
    return $_[2];
}

1;
