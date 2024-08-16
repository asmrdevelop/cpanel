#                                     Copyright 2024 WebPros International, LLC
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Plugins::Components;

use cPstrict;
use Cpanel::PluginManager ();
use File::Find::Rule      ();

use Moo;

our $LOAD_BASE       = '/usr/local/cpanel';
our $COMPONENTS_PATH = "$LOAD_BASE/Cpanel/Plugins/Components";

=head1 MODULE

C<Cpanel::Plugins::Components>

=head1 DESCRIPTION

C<Cpanel::Plugins::Components.pm> provides tools to load component lists for a targeted application
(cpanel, webmail, or whostmgr) and feature (APP_KEY).

=head1 SYNOPSIS

  use Cpanel::Plugins::Components ();
  my $components = get_components('cpanel', 'tools');

=head1 FUNCTIONS

=head2 get_components($APP, $APP_KEY)

Retrieve the list of components to be injected into the $APP and $APP_KEY where:

$APP - string - one of: cpanel, webmail, or whostmgr

$APP_KEY - string - unique key defined in the dynamic-ui.conf or in a plugins configuration.

=cut

sub get_components ( $app, $app_key ) {

    # Some pages may not have an app_key.
    return if !$app_key;

    my @plugins = (
        _load_dynamic_components( $app, $app_key ),
        _load_static_components( $app, $app_key ),
    );

    # Organize the components by slot
    my %by_slot;
    foreach my $component (@plugins) {

        # Filter out any that are disabled
        my $enabled = $component->is_enabled();
        if ( ref $enabled ) {
            $enabled = $$enabled;
        }
        next if $enabled != 1;
        push $by_slot{ $component->slot() }->@*, $component;
    }

    # Sort the items in the slots
    foreach my $slot ( keys %by_slot ) {
        my @unsorted = ref $by_slot{$slot} eq 'ARRAY' ? $by_slot{$slot}->@* : ();
        my @sorted   = sort { $a->priority <=> $b->priority } @unsorted;
        $by_slot{$slot} = \@sorted;
    }

    return \%by_slot;
}

=head2 _load_dynamic_components ( $APP, $APP_KEY )

Find and instantiate any dynamic components for this application and page.

=cut

sub _load_dynamic_components ( $app, $app_key ) {
    my $safe_module_name = _normalize_app_key($app_key);
    $safe_module_name =~ tr/-/_/;

    my $namespace = "Cpanel::Plugins::Components::${app}::${safe_module_name}";

    my @components;
    eval {
        my $manager = Cpanel::PluginManager->new( directories => [$LOAD_BASE], namespace => $namespace );
        $manager->load_all_plugins();
        @components = $manager->get_loaded_plugins();
    };
    if ( my $exception = $@ ) {
        say STDERR "Failed to load module based components: $exception";
    }
    return @components;
}

=head2 _load_static_components ( $APP, $APP_KEY )

Find and generate object wrappers around the components defined in JSON and YAML formats only.

=cut

sub _load_static_components ( $app, $app_key ) {
    my $safe_app_key = _normalize_app_key($app_key);
    my $path         = "$COMPONENTS_PATH/${app}/${safe_app_key}";
    return () if !-d $path;

    my $rule  = File::Find::Rule->new();
    my @paths = $rule->or( $rule->new()->file->name('*.yaml'), $rule->new()->file->name('*.json') )->in($path);

    my @components;
    foreach my $path (@paths) {
        my $component;
        eval {
            if ( $path =~ /\.yaml$/ ) {
                require Cpanel::Plugins::Components::YAML;
                $component = Cpanel::Plugins::Components::YAML->new($path);
            }
            elsif ( $path =~ /\.json$/ ) {
                require Cpanel::Plugins::Components::JSON;
                $component = Cpanel::Plugins::Components::JSON->new($path);
            }
        };
        if ( my $exception = $@ ) {
            say STDERR "Failed to load $path component with exception: $exception";
            next;
        }
        push @components, $component;
    }
    return @components;
}

=head2 _normalize_app_key ( $APP_KEY )

Normalize the app_key

=cut

sub _normalize_app_key ($app_key) {
    my $safe_app_key = $app_key;
    $safe_app_key =~ tr/-/_/;
    return $safe_app_key;
}

1;
