#                                     Copyright 2024 WebPros International, LLC
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Plugins::Components::JSON;

use cPstrict;
use Moo;
use File::Slurper qw/read_text/;
use JSON::XS      qw/decode_json/;

extends 'Cpanel::Plugins::Components::Base';

=head1 MODULE

C<Cpanel::Plugins::Components::JSON>

=head1 DESCRIPTION

C<Cpanel::Plugins::Components::JSON> is a Component class used to load Components from a JSON file format.

Place page specific components in the following folder by application context:

- ./Cpanel/Plugins/Components/cpanel/{app_key}/*  - components for the cpanel ui
- ./Cpanel/Plugins/Components/webmail/{app_key}/* - components for the webmail ui
- ./Cpanel/Plugins/Components/whm/{app_key}/*     - components for the whm ui

The {app_key} is used to target a specific page. You can find the {app_key} for a specific page
in the dynamic_ui.conf or the plugin.json file.

=head1 SYNOPSIS

A minimal implementation is:

  {
    "markup": "<a>hello</a>"
  }

You can override any of the properties depending on what you want to
accomplish with the plugin. Here is an example with the markup and css block
overridden.

  {
    "css": ".marble { color: white }",
    "markup": "<a class="marble">hello</a>",
    "slot": "right-nav",
  }

=head1 CONSTRUCTOR

=head2 new($path)

C<$path> is the path to a JSON file containing the static configuration for a component.

=cut

around BUILDARGS => sub {
    my ( $orig, $class, @args ) = @_;

    return { path => $args[0] }
      if @args == 1 && !ref $args[0];

    return $class->$orig(@args);
};

sub BUILD {
    my ( $self, $args ) = @_;
    my $content   = File::Slurper::read_text( $args->{path} ) or die "Cannot load component JSON file: $args->{path}";
    my $component = JSON::XS::decode_json($content);
    $self->{_component} = $component;
    $self->{_base}      = Cpanel::Plugins::Components::Base->new();
    return;
}

=head1 PROPERTIES

=head2 optional, string

display name for the plugin/component

=cut

has '+name' => (
    builder => '_build_name',
    lazy    => 1,
);

sub _build_name ($self) {
    return $self->{_component}{name} if $self->{_component} && defined $self->{_component}{name};
    return $self->{_base}->name();
}

=head2 optional, string

description for the plugin/component

=cut

has '+description' => (
    builder => '_build_description',
    lazy    => 1,
);

sub _build_description ($self) {
    return $self->{_component}{description} if $self->{_component} && defined $self->{_component}{description};
    return $self->{_base}->description();
}

=head2 optional, string

source for the plugin/component

=cut

has '+source' => (
    builder => '_build_source',
    lazy    => 1,
);

sub _build_source ($self) {
    return $self->{_component}{source} if $self->{_component} && defined $self->{_component}{source};
    return $self->{_base}->source();
}

=head2 keywords optional, string[]

keywords related to the plugin/component

=cut

has '+keywords' => (
    builder => '_build_keywords',
    lazy    => 1,
);

sub _build_keywords ($self) {
    return $self->{_component}{keywords} if $self->{_component} && defined $self->{_component}{keywords};
    return $self->{_base}->keywords();
}

# optional, markup string to render the plugin or sub returning such markup.
has '+markup' => (
    builder => '_build_markup',
    lazy    => 1,
);

sub _build_markup ($self) {
    return $self->{_component}{markup} if $self->{_component} && defined $self->{_component}{markup};
    return $self->{_base}->markup();
}

# optional, js string to render the plugin or sub returning such js.
has '+js' => (
    builder => '_build_js',
    lazy    => 1,
);

sub _build_js ($self) {
    return $self->{_component}{js} if $self->{_component} && defined $self->{_component}{js};
    return $self->{_base}->js();
}

# optional, url for js to load into the page for the plugin/component.
has '+js_url' => (
    builder => '_build_js_url',
    lazy    => 1,
);

sub _build_js_url ($self) {
    return $self->{_component}{js_url} if $self->{_component} && defined $self->{_component}{js_url};
    return $self->{_base}->js_url();
}

# optional, css string to render the plugin or sub returning such css.
has '+css' => (
    builder => '_build_css',
    lazy    => 1,
);

sub _build_css ($self) {
    return $self->{_component}{css} if $self->{_component} && defined $self->{_component}{css};
    return $self->{_base}->css();
}

# optional, url for css to load into the page for the plugin/component.
has '+css_url' => (
    builder => '_build_css_url',
    lazy    => 1,
);

sub _build_css_url ($self) {
    return $self->{_component}{css_url} if $self->{_component} && defined $self->{_component}{css_url};
    return $self->{_base}->css_url();
}

# optional, meta block to load for the plugin/component.
has '+meta' => (
    builder => '_build_meta',
    lazy    => 1,
);

sub _build_meta ($self) {
    return $self->{_component}{meta} if $self->{_component} && defined $self->{_component}{meta};
    return $self->{_base}->meta();
}

# optional, named slot on the page.
has '+slot' => (
    builder => '_build_slot',
    lazy    => 1,
);

sub _build_slot ($self) {
    return $self->{_component}{slot} if $self->{_component} && defined $self->{_component}{slot};
    return $self->{_base}->slot();
}

# optional, named slot on the page.
has '+process' => (
    builder => '_build_process',
    lazy    => 1,
);

sub _build_process ($self) {
    return ( $self->{_component}{process} ? \1 : \0 ) if $self->{_component} && defined $self->{_component}{process};
    return $self->{_base}->process();
}

# check if the component is enabled.
has '+is_enabled' => (
    builder => '_build_is_enabled',
    lazy    => 1,
);

sub _build_is_enabled ($self) {
    return ( $self->{_component}{is_enabled} ? \1 : \0 ) if $self->{_component} && defined $self->{_component}{is_enabled};
    return $self->{_base}->is_enabled();
}

# the priority of the plugin within the slot
has '+priority' => (
    builder => '_build_priority',
    lazy    => 1,
);

sub _build_priority ($self) {
    return $self->{_component}{priority} if $self->{_component} && defined $self->{_component}{priority};
    return $self->{_base}->priority();
}

1;
