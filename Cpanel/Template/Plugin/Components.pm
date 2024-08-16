#                                     Copyright 2024 WebPros International, LLC
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Template::Plugin::Components;

use cPstrict;

use base 'Template::Plugin';

use Cpanel::Plugins::Components ();

=head1 MODULE

C<Cpanel::Plugins::Components>

=head1 DESCRIPTION

C<Cpanel::Plugins::Components.pm> provides helpers used to load components into slots defined in the cpanel, webmail and whostgr apps.

=head1 SYNOPSIS

  USE Components;
  IF Components.has_components_for('cpanel', 'tools', 'menu-top');
    PROCESS "_assets/component.html.tt",
        APP_KEY => 'tools',
        TAG     => 'div',
        SLOT    => 'menu-top';
  END


=head1 CONSTRUCTOR

=head2 $CLASS->new($CONTEXT, $ARGS)

Called by USE in TT to create the Template::Plugin instance.

=cut

sub new {
    my ( $class, $context, @args ) = @_;
    my $plugin = { _CONTEXT => $context };
    bless $plugin, $class;
    return $plugin;
}

my %app_cache;

=head1 METHODS

=head2 $PLUGIN->get_components($APP, $APP_KEY)

Fetch a list of components for the $APP and $APP_KEY

$APP - string - one of: cpanel, webmail, or whostmgr

$APP_KEY - string - unique key defined in the dynamic-ui.conf or in a plugins configuration.

=cut

sub get_components ( $plugin, $app, $app_key ) {
    if ( !$app_cache{$app}{$app_key} ) {
        $app_cache{$app}{$app_key} = Cpanel::Plugins::Components::get_components( $app, $app_key );
    }

    return $app_cache{$app}{$app_key};
}

=head2 $PLUGIN->has_components_for($APP, $APP_KEY, $SLOT)

Check if there are any components registered to fill the $APP, $APP_KEY, $SLOT position in the UI.

$APP - string - one of: cpanel, webmail, or whostmgr

$APP_KEY - string - unique key defined in the dynamic-ui.conf or in a plugins configuration.

$SLOT - string - the name of the slot on the specificed page or in the wrapper.

=cut

sub has_components_for ( $plugin, $app, $app_key = 'home', $slot = 'default' ) {
    my $components = $plugin->get_components( $app, $app_key );
    return 0 if !$components || ref $components ne 'HASH' || !keys $components->%*;
    my $list = $components->{$slot};
    return 0 if !$list || ref $list ne 'ARRAY';

    return 1 if scalar $list->@*;

    return 0;
}

=head2 $PLUGIN->render_component($COMPONENT, $ARGS)

Render the component into the UI at the spot its defined. See the C<component.html.tt> templates for more details.

=cut

sub render_component ( $plugin, $component, $args ) {
    $component->render(
        $args,
        {
            _CONTEXT => $plugin->{_CONTEXT},
        }
    );
}

sub flush_cache ($plugin) {
    %app_cache = ();
}

1;
