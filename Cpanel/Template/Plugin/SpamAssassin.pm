package Cpanel::Template::Plugin::SpamAssassin;

# cpanel - Cpanel/Template/Plugin/SpamAssassin.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Template::Plugin::SpamAssassin

=head1 SYNOPSIS

    USE SpamAssassin;

    SET default = SpamAssassin.DEFAULT_REQUIRED_SCORE;

=head1 DESCRIPTION

This plugin exposes the constants from
L<Cpanel::SpamAssassin::Constants>. See that module for a full list of
available constants.

=cut

use parent qw(
  Template::Plugin
  Cpanel::SpamAssassin::Constants
);

1;
