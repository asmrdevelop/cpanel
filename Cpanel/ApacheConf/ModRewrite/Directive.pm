package Cpanel::ApacheConf::ModRewrite::Directive;

# cpanel - Cpanel/ApacheConf/ModRewrite/Directive.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

#Subclasses must implement these methods!
sub DIRECTIVE_NAME  { ... }
sub new_from_string { ... }

1;
