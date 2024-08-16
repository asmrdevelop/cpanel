package Cpanel::Template::Plugin::CPPrivate;

# cpanel - Cpanel/Template/Plugin/CPPrivate.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#####
# This plugin overrides Template::Toolkit's default behavior of
# considering anything with a leading underscore or period as a
# private variable or method. Useful for dealing with data that
# originates outside Template::Toolkit.

use strict;

use base 'Template::Plugin';

use Template::Stash;

#even override stash classes use this variable,
#e.g. Template::Stash::XS and Cpanel::Template::Stash
$Template::Stash::PRIVATE = q{};

1;
