package Cpanel::Module::Load;

# cpanel - Cpanel/Module/Load.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Module::Load

=head1 SYNOPSIS

    use Cpanel::Module::Load;

    #...then CPAN code can do:
    Module::Load::load($module_name);

    #...without actually loading Module/Load.pm

=head1 DESCRIPTION

The core module L<Module::Load> is used in some CPAN modules.
We have L<Cpanel::LoadModule> for this purpose and don’t really want
to load a 2nd module to do the same work, so the present module
stubs out C<Module::Load::load()>. This allows us to use those CPAN
modules without bringing in a 2nd loader module.

=cut

use Cpanel::LoadModule ();

{

    package Module::Load;
}

*Module::Load::load = *Cpanel::LoadModule::load_perl_module;

BEGIN {
    $INC{'Module/Load.pm'} = __FILE__;    ##no critic qw(Variables::RequireLocalizedPunctuationVars)
}

1;
