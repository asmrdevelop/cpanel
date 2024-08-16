package Cpanel::Component;

# cpanel - Cpanel/Component.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Debug             ();
use Cpanel::Component::Cache  ();
use Cpanel::Config::ConfigObj ();

our $COMPONENTS_CONFIG_PATH = '/var/cpanel/plugins/config.json';
my $COMPONENTS_CACHE;

=head1 NAME

Cpanel::Component - Reads the /var/cpanel/plugins/config.json file for optional
software components which can be enabled or disabled on cPanel server;

=head1 SYNOPSIS

    my $component_helper = Cpanel::Component::init();

    # Update the related data for a component
    my $updated = $component_helper->set_component_value('my-plugin', $arb_data);
    if ($updated) {
        $component_helper->save();
    }

    # Get list of components and their value
    my $component_hr = $component_helper->get_components();

    # Make a comma separated representation of key/value pairs
    my $comma_separated_line = join(
        ",",
        map { $_ . '=' . $component_hr->{$_}  keys %{$component_hr}
    ) . "\n";

    ####
    # Simply retrive the last stored state
    my $component_helper_on_disk = Cpanel::Component::Cache::fetch();
    my @active_components = keys %{$component_helper_on_disk->{'components'}};

=head1 DESCRIPTION

This module is used to manage optional software components on a cPanel Server.

Plugins or cPanel distributed code should add entries for their systems to the /var/cpanel/plugins/config.json file.
So if your feature is called: unique-name, add the entry to this file as follows:

    {
        'unique-name': {}
    }

Cpanel::Components are tied to driver modules. When you add a new optional product feature using this system,
you need to also add a modules that implements:

    Cpanel::Config::ConfigObj::Interface::Config::v1

and possibly one or more of the optional interfaces:

    Cpanel::Config::ConfigObj::Interface::Cpanel
    Cpanel::Config::ConfigObj::Interface::Whostmgr
    Cpanel::Config::ConfigObj::Interface::License

depending on what your feature or plugin wants to take control of in the interface.

=head1 STATIC METHODS

=head2 CLASS->base()

Get a blessed ref to the Component.

In most cases you should be using C<init()> instead.

=cut

sub base {
    my ($class) = @_;

    my $self = bless {

        # cachable component information
        'components' => {},

        # list of components we will load.
        # also contains any non-cachable data related to
        # the component like: localized strings, dynamic rules that depend on
        # the server state or logged in user, or similar.
        'observed_components' => _components_to_observe(),

        # interface to plugin and buildin "drivers" - some may be from third parties.
        'software_interface' => undef

    }, $class;

    return $self;
}

=head2 CLASS->init($FORCE_UPDATE, $SAVE_ON_DEMAND)

Instantiate a C<Component>.

=cut

sub init {
    my ( $class, $force_update ) = @_;
    $force_update ||= 0;
    my $component_helper = $class->base();
    return $component_helper->load($force_update);
}

=head2 INSTANCE->save()

Write this objects properties to cache

=cut

sub save {
    my ($self) = @_;

    return if $> != 0;    # Only root can do this, not a cPanel user.

    return Cpanel::Component::Cache::save(
        {
            'components' => $self->{'components'} || {},
        },
        'info'
    );
}

=head2 INSTANCE->has_registered_components()

Check if there are any components that are 'active'.

SEE: C<Cpanel::LicenseComnponent::Cache::has_registered_components> if you dont need a refreshed list.

=head3 RETURNS

1 if there are active registred components or 0 otherwise.

=cut

sub has_registered_components {
    my ($self) = @_;
    return ( keys %{ $self->{'components'} } ) ? 1 : 0;
}

=head2 INSTANCE->has_component(@COMPONENTS)

Check if all the passed components are actively registered.

SEE: C<Cpanel::LicenseComnponent::Cache::has_components> if you dont need a refreshed list.

=head3 RETURNS

1 if all are registered, 0 otherwise.

=cut

sub has_component {
    my ( $self, @components ) = @_;
    foreach my $component (@components) {
        return 0 unless exists $self->{'components'}->{$component};
    }
    return 1;
}

=head2 INSTANCE->set_component_value($NAME, $VALUE)

Assign a value to a registered component

=head3 ARGUMENTS

=over

=item $NAME - string - The name of the component

=item $VALUE - hashref - that should jive with the data returned from the respective register components. ???

=back

=head3 RETURNS

1 on success, or 0 if:

=over

=item component isn't an present license flag

=item component is not usually registered/unregistered

=item component is currently not registered

=back

=cut

sub set_component_value {
    my ( $self, $component_name, $value ) = @_;
    if (   !exists $self->{'observed_components'}->{$component_name}
        || !exists $self->{'components'}->{$component_name} ) {
        return 0;
    }

    $value = ( ref $value ne 'HASH' ) ? {} : $value;

    if ( ref $self->{'components'}->{$component_name} eq 'HASH' ) {
        %{ $self->{'components'}->{$component_name} } = map { ( exists $value->{$_} ) ? ( $_ => $value->{$_} ) : (); } keys %{ $self->{'components'}->{$component_name} };
        delete $self->{'components'}->{$component_name}->{''};
    }

    return 1;
}

=head2 INSTANCE->get_component_value($NAME)

Get the value of a registered component.

=head3 ARGUMENTS

=over

=item $NAME - string - the component name.

=back

=head3 RETURNS

A hashref with the components saved values.

=cut

sub get_component_value {
    my ( $self, $component_name ) = @_;
    if ( $self->{'components'}->{$component_name} ) {
        return $self->{'components'}->{$component_name} || {};
    }
    return {};
}

=head2 INSTANCE->get_components()

Gets registered components.

=head3 RETURNS

A hashref where the keys are the component name and the value is
anything assigned by a registration worker or a call to C<set_component_value()>.

=cut

sub get_components {
    my ($self) = @_;
    my $s_copy = { %{ $self->{'components'} } };
    return $s_copy;
}

=head2 INSTANCE->get_component_configured_status(@COMPONENTS)

Gets the configured status for the list of components

=head3 ARGUMENTS

=over

=item @COMPONENTS - list of components to check

=back

=head3 RETURNS

A hashref with each key being one of the requested components and the value be it he status of that component.

The values be true when the component is a currently registered component & the
C<check> routine returns true (see check_component(); default 1)

=cut

sub get_component_configured_status {
    my ( $self, @components ) = @_;
    my %result;
    foreach (@components) {
        if (   ( exists $self->{'components'}->{$_} )
            && ( $self->check_component($_) ) ) {
            $result{$_} = 1;
        }
        else {
            $result{$_} = 0;
        }
    }
    return \%result;
}

=head2 INSTANCE->get_features_keyby_component($LOAD_ALL)

Gets the configured status for the list of components

=head3 ARGUMENTS

=over

=item $LOAD_ALL - boolean - When true will load all the possible components.

=back

=head3 RETURNS

A hashref whose keys are the component name and values are arrayref of feature names

=cut

sub get_features_keyby_component {
    my ( $self, $load_all_possible ) = @_;
    my $features_by_component = {};
    my $features_by_items     = $self->get_component_features($load_all_possible);
    foreach my $feature_item ( sort keys %{$features_by_items} ) {
        push @{ $features_by_component->{ $features_by_items->{$feature_item} } }, $feature_item;
    }

    return $features_by_component;
}

=head2 INSTANCE->get_feature_details_keyby_component($LOAD_ALL)

Gets the configured status for the list of components

=head3 ARGUMENTS

=over

=item $LOAD_ALL - boolean - When true will load all the possible components.

=back

=head3 RETURNS

A HASHREF whose keys are the component name and values are arrayref of feature HASHREF where
each HASHREF has the following structure:

=over

=item name - string - Name of the feature.

=item description - string - Description of the feature.

=item default_value - boolean - 1 when enabled by default, 0 when disabled by default.

=item is_addon - boolean - 1 when the component was installed as an addon.

=item is_plugin - boolean - 1 when the component was installed as a modern plugin.

=back

=cut

sub get_feature_details_keyby_component {
    my ( $self, $load_all_possible ) = @_;
    my %features;

    my $all_components  = $self->{'observed_components'};
    my @component_names = $self->_get_component_names($load_all_possible);

    foreach my $component_name (@component_names) {

        if (   ( !exists $all_components->{$component_name}{'features'} )
            || ( ref $all_components->{$component_name}{'features'} ne 'ARRAY' ) ) {
            next;
        }

        foreach my $item ( @{ $all_components->{$component_name}{'features'} } ) {
            if (   ( ref $item ne 'HASH' )
                || ( !exists $item->{'name'} )
                || ( !defined $item->{'name'} ) ) {
                next;
            }
            $features{$component_name} = $all_components->{$component_name}->{'features'};
        }

    }
    return \%features;
}

=head2 INSTANCE->get_component_features($LOAD_ALL)

Gets the configured status for the list of components

=head3 ARGUMENTS

=over

=item $LOAD_ALL - boolean - When true will load all the possible components.

=back

=head3 RETURNS

A HASHREF where the keys are the feature name and the value is a reference to the component that controls that feature.

=cut

sub get_component_features {
    my ( $self, $load_all_possible ) = @_;
    my %features;

    my $all_components = $self->{'observed_components'};
    my @components     = $self->_get_component_names($load_all_possible);

    foreach my $component_name (@components) {
        next if !exists $all_components->{$component_name}{'features'};
        foreach my $item ( @{ $all_components->{$component_name}->{'features'} } ) {
            next if ref $item ne 'HASH' || !exists $item->{'name'};
            $features{ $item->{'name'} } = $component_name;
        }
    }
    return \%features;
}

sub contact_descriptions {
    my ( $self, $kind, $load_all_possible ) = @_;
    $kind //= 'whm';

    my %notifications;

    my $all_components = $self->{'observed_components'};
    my @components     = $self->_get_component_names($load_all_possible);

    foreach my $component_name (@components) {
        my $app_notifications = $all_components->{$component_name}{'notifications'}{$kind};
        next if !$app_notifications;
        foreach my $name ( keys %{$app_notifications} ) {
            my $notification = $app_notifications->{$name};

            next
              if ref $notification ne 'HASH'
              || !exists $notification->{'display_name'};

            $notifications{$name} = $notification;
        }
    }
    return \%notifications;
}

=head2 INSTANCE->load($FORCE)

Load the components from the stored cache.

=head3 ARGUMENTS

=over

=item $FORCE - boolean - When true, force an update of the component registration cache.

=back

=head3 RETURNS

Reference to the current instance.

=cut

sub load {
    my ( $self, $force_update ) = @_;
    my $cache;

    if ( !$self->{'software_interface'} ) {
        $self->set_software_interface( Cpanel::Config::ConfigObj->new() );
    }

    if ( $force_update || Cpanel::Component::Cache::expired() ) {
        $self->update_registrations();
        $self->save();
    }
    else {

        # fetch a cache store
        $cache = Cpanel::Component::Cache::fetch();

        if ( _set_diff( [ keys %{ $cache->{'components'} } ], [ keys %{ $self->{'observed_components'} } ] )
            || grep { !defined $cache->{'components'}{$_} } keys %{ $cache->{'components'} } ) {
            $self->update_registrations();
            $self->save();
        }
        else {
            # The same components are being observed as previously
            $self->{'components'} = $cache->{'components'};

            # Refresh the component data (acls, features, ...)
            foreach my $component ( keys %{ $self->{'observed_components'} } ) {
                my $driver = $self->_get_driver($component);
                next if !$driver;

                $self->_load_component( $component, $driver );

                # We do not load the license data here since its already present if applicable.
            }
        }
    }

    return $self;
}

=head2 INSTANCE->set_software_interface($OBJ)

Setter for the software_interface property. This will validate the input C<$OBJ> is valid before setting it.

=head3 ARGUMENTS

=over

=item $OBJ - HASHREF

=back

=head3 RETURNS

1 when the setter succeeds, undef otherwise.

=cut

sub set_software_interface {
    my ( $self, $obj ) = @_;

    if ( !$obj->isa('Cpanel::Config::ConfigObj') ) {
        Cpanel::Debug::log_warn("Invalid object argument");
        return;
    }
    $self->{'software_interface'} = $obj;
    return 1;
}

=head2 INSTANCE->get_software_interface()

Getter for the software_interface property.

=head3 RETURNS

C<Cpanel::Config::ConfigObj> instance.

=cut

sub get_software_interface {
    my ($self) = @_;
    return $self->{'software_interface'};
}

=head2 INSTANCE->update_registrations()

Update the components after changes on disk or plugin installs.

=cut

sub update_registrations {
    my ($self) = @_;
    foreach my $component ( keys %{ $self->{'observed_components'} } ) {

        my $driver = $self->_get_driver($component);
        next if !$driver;

        $self->_load_component( $component, $driver );
        $self->_load_license( $component, $driver );
    }
    return;
}

=head1 PRIVATE STATIC METHODS

=head2 _components_to_observe()

Helper that loads the list of components we want to observe from the file

    /var/cpanel/plugins/config.json

if it exists.

=head3 RETURNS

The list of components is stored as a HASHREF where the keys are the name of the component
The value for each key is a HASHREF that contains information related to that component.

=cut

sub _components_to_observe {
    return _update_observed_components_cache();
}

=head2 _update_observed_components_cache($FORCE)

Update the local in memory cache.

=head3 ARGUMENTS

=over

=item $FORCE - boolean - optional

If true the in memory cache will be reloaded with the /var/cpanel/plugin/config.json contents.
Otherwise only loads the cache if its undefined.

=back

=head3 RETURNS

HASHREF where the keys are the component names and the values are a HASHREF with additional
information related to that component.

=cut

sub _update_observed_components_cache {
    my $force = shift;

    if ( !$COMPONENTS_CACHE || $force ) {
        $COMPONENTS_CACHE = {};

        eval {
            require Cpanel::JSON;
            $COMPONENTS_CACHE = Cpanel::JSON::LoadFile($COMPONENTS_CONFIG_PATH);
        };
    }
    return $COMPONENTS_CACHE;
}

=head1 PRIVATE METHODS

=head2 INSTANCE->check_component($NAME)

Check if the component is enabled.

=head3 RETURNS

=over

=item 0 - if the component is not observed

=item boolean - The value returned by the C<DRIVER->check()> routine.

=item 1 - if no C<DRIVER->check()> method is present. Assume the feature is not conditional.

=back

=cut

sub check_component {
    my ( $self, $component_name ) = @_;

    my $driver = $self->{'software_interface'}->get_driver($component_name);

    return 0 if !$driver;

    if ( $driver->can('check') ) {
        return $driver->check();
    }

    return 1;
}

=head2 INSTANCE->_load_component($COMPONENT, $DRIVER)

Preload the various parts of the dynamic data for the specific component.

=cut

sub _load_component {
    my ( $self, $component, $driver ) = @_;
    $self->_load_features( $component, $driver );
    $self->_load_notifictions( $component, $driver );
    return;
}

=head2 INSTANCE->_load_features($COMPONENT, $DRIVER)

Preload the feature descriptions for the specific component.

=cut

sub _load_features {
    my ( $self, $component, $driver ) = @_;
    if ( $driver->isa('Cpanel::Config::ConfigObj::Interface::Cpanel') ) {
        $self->{'observed_components'}->{$component}->{'features'} = $driver->featurelist_desc();
    }

    return;
}

=head2 INSTANCE->_load_notifictions($COMPONENT, $DRIVER)

Preload the notification descriptions for the specific component.

=cut

sub _load_notifictions {
    my ( $self, $component, $driver ) = @_;
    if ( $driver->isa('Cpanel::Config::ConfigObj::Interface::Cpanel') && $driver->can('contact_descriptions') ) {
        $self->{'observed_components'}{$component}{'notifications'}{'cpanel'} = $driver->contact_descriptions('cpanel');
    }

    if ( $driver->isa('Cpanel::Config::ConfigObj::Interface::Whostmgr') && $driver->can('contact_descriptions') ) {
        $self->{'observed_components'}{$component}{'notifications'}{'whm'} = $driver->contact_descriptions('whm');
    }

    return;
}

=head2 INSTANCE->_load_license($COMPONENT, $DRIVER)

Preload the the licnese information for the specific component.

=cut

sub _load_license {
    my ( $self, $component, $driver ) = @_;
    if ( $driver->isa('Cpanel::Config::ConfigObj::Interface::License') ) {
        $self->{'components'}->{$component} = $driver->license_data() || {};
    }
    else {
        $self->{'components'}->{$component} = {};
    }
    return;
}

=head2 INSTANCE->_get_driver($COMPONENT)

Helper to fetch the driver for a given C<$COMPONENT> name.

=cut

sub _get_driver {
    my ( $self, $component ) = @_;
    my $driver = $self->{'software_interface'}->get_driver($component);
    if ( !$driver ) {
        Cpanel::Debug::log_warn("Could not get driver '$component'");
        return;
    }
    return $driver;
}

=head2 INSTANCE->_get_component_names($ALL)

Helper to retrieve a list of component_names.

=head3 RETURNS

All the components if the C<$ALL> flag is passed and true. Or just the enabled component names if
the C<$ALL> flag is not passed or is false.

=cut

sub _get_component_names {
    my ( $self, $all ) = @_;

    my $all_components = $self->{'observed_components'};
    my @components;
    if ($all) {
        @components = keys %{$all_components};
    }
    else {
        my $status = $self->get_component_configured_status( keys %{ $self->{'components'} } );
        @components = map { ( $status->{$_} ) ? $_ : () } keys %{$status};
    }

    return @components;
}

=head2 _set_diff($A, $B)

Compare the two sets for differences.  $A - $B

=cut

sub _set_diff {
    my ( $a, $b ) = @_;
    my @difference;
    foreach my $item (@$a) {
        push @difference, $item unless grep { $item eq $_ } @$b;
    }
    return @difference;
}

1;
