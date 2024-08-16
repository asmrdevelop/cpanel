package Cpanel::Template::Plugin::Menu;

# cpanel - Cpanel/Template/Plugin/Menu.pm          Copyright 2023 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use base 'Template::Plugin';

=head1 NAME

Cpanel::Template::Plugin::Menu

=head1 DESCRIPTION

Plugin that is used to calculate menus. This uses the C<Cpanel/Plugin/Menu> system to generate the menus.

=head1 METHODS

=head2 C<load(CLASS, CONTEXT)>

Internal method that is called when the plugin loads.

=head3 Arguments

Arguments are positional.

=over

=item CLASS - string - Class name of this plugin

=item CONTEXT - object - Template toolkit context.

=back

=head3 Returns

See documentation in Template Toolkit Plugin API for expected return type.

=cut

sub load ( $class, $context ) {
    my $stash = $context->stash();
    @{$stash}{
        'get_menu_by_name',
      } = (
        sub ($name) {
            require Cpanel::Plugins::MenuBuilder;
            return Cpanel::Plugins::MenuBuilder::load_menu($name);
        }
      );

    return $class->SUPER::load($context);
}

1;
