#                                     Copyright 2024 WebPros International, LLC
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Plugins::Components::Base;

use cPstrict;
use Moo;

=head1 MODULE

C<Cpanel::Plugins::Components::Base>

=head1 DESCRIPTION

C<Cpanel::Plugins::Components::Base> is a base class for rendering components into pages.

Components should be small self contained mini-applications.

Place any more specialized base class in ./Cpanel/Plugins/Components/*.

Place page specific components in the following folder by application context:

- ./Cpanel/Plugins/Components/cpanel/{app_key}/*  - components for the cpanel ui
- ./Cpanel/Plugins/Components/webmail/{app_key}/* - components for the webmail ui
- ./Cpanel/Plugins/Components/whm/{app_key}/*     - components for the whm ui

The {app_key} is used to target a specific page. You can find the {app_key} for a specific page
in the dynamic_ui.conf or the plugin.json file.

=head1 SYNOPSIS

A minimal implementation is:

  extends 'Cpanel::Plugins::Components::Base';

  has "+markup" => (
    default => '<a>hello</a>'
  );

You can override any of the properties depending on what you want to
accomplish with the plugin. Here is an example with the markup and css block
overridden.

  extends 'Cpanel::Plugins::Components::Base';

  has "+css" => (
    default => sub { '.marble { color: white }' },
  );

  has "+markup" => {
    default => sub { '<a class="marble">hello</a>' },
  );

=head1 PROPERTIES

=head2 optional, string

display name for the plugin/component

=cut

has 'name' => (
    is      => 'ro',
    default => "",
);

=head2 optional, string

description for the plugin/component

=cut

has 'description' => (
    is      => 'ro',
    default => '',
);

=head2 optional, string

source for the plugin/component

=cut

has 'source' => (
    is      => 'ro',
    default => '',
);

=head2 keywords optional, string[]

keywords related to the plugin/component

=cut

has 'keywords' => (
    is      => 'ro',
    default => sub { [] },
);

# optional, markup string to render the plugin or sub returning such markup.
has 'markup' => (
    is      => 'ro',
    default => undef,
);

# optional, js string to render the plugin or sub returning such js.
has 'js' => (
    is      => 'ro',
    default => undef,
);

# optional, url for js to load into the page for the plugin/component.
has 'js_url' => (
    is      => 'ro',
    default => undef,
);

# optional, css string to render the plugin or sub returning such css.
has 'css' => (
    is      => 'ro',
    default => undef,
);

# optional, url for css to load into the page for the plugin/component.
has 'css_url' => (
    is      => 'ro',
    default => undef,
);

# optional, meta block to load for the plugin/component.
has 'meta' => (
    is      => 'ro',
    default => undef,
);

# optional, named slot on the page.
has 'slot' => (
    is      => 'ro',
    default => 'default',
);

# optional, named slot on the page.
has 'process' => (
    is      => 'ro',
    default => sub { \0 },    # defaults to not tt processed
);

# check if the component is enabled.
has 'is_enabled' => (
    is      => 'ro',
    default => sub { \1 },    # defaults to enabled.
);

# the priority of the plugin within the slot
has 'priority' => (
    is      => 'ro',
    default => 1,             # defaults to priority 1.
);

my $_template;

sub get_template ( $self, $options ) {
    if ( !$_template ) {
        require Template;
        $_template = Template->new($options);
    }
    return $_template;
}

sub render ( $self, $args, $options ) {
    if ( $self->process ) {
        my $output;
        $self->get_template($options)->process( \$self->markup, $args, \$output );
        return $output;
    }
    else {
        return $self->markup;
    }
}

1;
