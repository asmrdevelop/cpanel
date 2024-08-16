package Cpanel::Config::ConfigObj::Interface::Config::v2;

# cpanel - Cpanel/Config/ConfigObj/Interface/Config/v2.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

# Super class for Cpanel::Config::ConfigObj::Driver::*

use cPstrict;

use parent qw(Cpanel::Config::ConfigObj::Interface::Driver);

use Cpanel::LoadModule ();
use Cpanel::Debug      ();

our $VERSION = 1.0;

sub new {
    my $defaults = {};
    my $class    = shift;
    $defaults->{'module_name'} = shift;
    my $args = shift;
    my $obj  = shift;

    $defaults->{'meta'} = {};

    %{$defaults} = ( %{$defaults}, %{$args} );

    if ( defined $obj ) {
        $obj = $class->SUPER::new( $defaults, $obj );
    }
    else {
        $obj = $defaults;
    }
    bless( $obj, $class );

    return $obj;
}

sub spec_actions {
    return {
        "info"     => "Print information about a feature.",
        "enable"   => "Set server configuration(s) of a feature to 'enabled'.",
        "disable"  => "Set server configuration(s) of a feature to 'disabled'.",
        "precheck" => "Perform a pre-check to determine whether the feature should be shown.",
    };
}

sub meta {
    my ($self) = @_;
    my $meta_obj = $self->interface()->fetch_meta_interface()->new();

    $meta_obj->set_locale_handle( $self->interface->get_locale_handle() );
    $meta_obj->set_meta_content_from_driver($self);

    return $meta_obj;
}

use constant spec_version => 2;

sub module_name { return shift->{'module_name'}; }
sub info        { return shift->meta()->abstract(); }

# These methods are assumed to be no-ops, and may be overriden

# "Turn on" a feature, used in feature showcases and auto-enabled features
sub enable {
    my ($self) = @_;

    if ( defined $self->{'enable'} ) {
        return $self->_handle_custom_method( 'enable', undef, 1 );
    }

    return 1;
}

# "Turn off" a feature, used in feature showcases.
sub disable {
    my ($self) = @_;

    if ( defined $self->{'disable'} ) {
        return $self->_handle_custom_method( 'disable', undef, 1 );
    }

    return 1;
}

# Perform a pre-check to determine whether the feature entry should be shown
sub precheck {    # maybe use precheck??
    my ( $self, $formref ) = @_;

    if ( defined $self->{'precheck'} ) {
        return $self->_handle_custom_method( 'precheck', $formref, () );
    }

    return 1;
}

# Handle form data from a feature showcase.
sub handle_showcase_submission {
    my ( $self, $formref ) = @_;

    if ( defined $self->{'handle_showcase_submission'} ) {
        return $self->_handle_custom_method( 'handle_showcase_submission', $formref, () );
    }

    return ();
}

# Set the default value of the radio button in feature showcase?
sub set_default {
    my ($self) = @_;

    if ( defined $self->{'set_default'} ) {
        return $self->_handle_custom_method( 'set_default', undef, 0 );
    }

    return 0;
}

# Deal with the renaming of the v1 version of this
sub check {
    return undef;
}

# What is the current value of the setting? Useful for Tweak Settings in a feature showcase.
sub status {
    my ($self) = @_;

    if ( defined $self->{'status'} ) {
        return $self->_handle_custom_method( 'status', undef, $self->set_default() );
    }

    return $self->set_default;
}

sub _handle_custom_method {
    my ( $self, $method, $formref, $default_return ) = @_;

    # $method will be a string, naming one of the overridable methods above
    # $formref will be the hash of form data being handed off from a fillable form
    # $default_return is primarly for testing and last-ditch fallback

    # Snag the JSON for the method.
    my $custom_method = $self->{$method};

    # They want the overridden method to always return a static value
    #
    if ( defined $custom_method->{'static'} ) {
        return $custom_method->{'static'};
    }

    # They want to call a method, with or without params
    #
    if ( defined $custom_method->{'module'} && defined $custom_method->{'method'} ) {

        my $module        = $custom_method->{'module'};
        my $module_method = $custom_method->{'method'};
        my $params        = $custom_method->{'params'};

        # Try to load the desired module
        #
        my $load_ok = eval { Cpanel::LoadModule::load_perl_module($module); };
        if ( !$load_ok ) {
            Cpanel::Debug::log_error("Failed to load module '$module'");
            return $default_return;
        }

        # If the method exists, get a ref to it
        #
        my $coderef = $module->can($module_method);
        if ( !$coderef ) {
            Cpanel::Debug::log_error("The '$module' does not have a method named '$module_method'");
            return $default_return;
        }

        # If we've been handed a formref, use values from it in the params.
        #
        if ( defined $formref ) {
            Cpanel::LoadModule::load_perl_module("JSON::XS");
            my $content = JSON::XS::encode_json($params);
            while ( $content =~ /FORM\(/ ) {
                my ( $start, $param, $end ) = $content =~ /(.*)FORM\((.*)\)(.*)/;
                if ( defined $formref->{$param} ) {
                    $content = $start . $formref->{$param} . $end;    #Sub in the form value
                }
                else {
                    $content = $start . $end;                         #False tag, just strip it.
                }
            }
            $params = JSON::XS::decode_json($content);
        }

        return &$coderef( map { _explode($_) } @$params );
    }

    #
    # They've improperly defined the custom method, so just return the default, but log the problem
    #
    Cpanel::Debug::log_error( "The custom '$method' method for the '" . $self->module_name() . "' ConfigObj module is improperly defined in the JSON definition." );
    return $default_return;
}

sub _explode ($param) {
    if ( $param eq '__EMPTY_CB__' ) {
        $param = sub { };
    }
    return $param;
}

1;
__END__

=encoding utf-8

=head1 NAME

Cpanel::Config::ConfigObj::Interface::Config::v2

=head1 SYNOPSIS

    Cpanel::Config::ConfigObj::Interface::Config::v2->new(
        "name_of_driver",
        $driver_descriptive_hr,
        $parent_ConfigObj);

=head1 DESCRIPTION

A class for ConfigObj v2 modules.

=cut

=head1 METHODS

=head2 Read-only informational methods

The following methods return information about the object; none take parameters

=over 4

=item B<spec_actions>

Returns a hashref with keys as available actions, and values as the description of the action.

=item B<meta>

Returns the metadata object for the driver.

=item B<spec_version>

Returns the version of the Config object specification.

=item B<module_name>

Returns the internal name of the module.

=item B<info>

Returns the abstract from the meta object for the driver.

=back

=head2 Other methods

Each of these methods is intended to be overriden by pointing to another module's subroutines in
the object-defining JSON

=over 4

=item B<enable>

"Turn on" a feature, used in feature showcases. Default return is 1.

=item B<disable>

"Turn off" a feature, used in feature showcases. Default return is 1.

=item B<precheck>

Perform a custom pre-check to determine whether the entry should be shown. If this attribute is
not defined in the JSON, no additional restrictions are imposed.

=item B<handle_showcase_submission>

Handle form input data in a feature showcase. Default return is 1.

=item B<set_default>

This sets the default radio button value on a feature showcase. Default return is 0.

=item B<status>

Is this feature currently enabled? Can be used in enable/disable logic. Default return is the value of set_default();

=back

=head2 Internal methods

=head3 B<_handle_custom_method>

This method processes and executes JSON-based customizations of the overridable methods B<enable>,
B<disable>, B<handle_showcase_submission>, B<set_default>, and B<status>. The parameters are:

=over 4

=item B<method>

The name of the method being overridden

=item B<form_data>

A hashref (or undef) of data coming from the fillable form in the feature showcase entry. To create one of these,
add HTML to the abstract of the feature showcase entry with input fields named; you'll get a hash to use right here,
which will be passed to your custom module code.

=item B<default_return>

A fallback return value (mostly implemented for testing)

=back
