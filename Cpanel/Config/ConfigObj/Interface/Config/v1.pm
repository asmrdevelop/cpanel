package Cpanel::Config::ConfigObj::Interface::Config::v1;

# cpanel - Cpanel/Config/ConfigObj/Interface/Config/v1.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

# Super class for Cpanel::Config::ConfigObj::Driver::*

use strict;
use warnings;

use Cpanel::Debug ();

use parent qw(
  Cpanel::Config::ConfigObj::Interface::Driver
  Cpanel::Config::ConfigObj::Interface::Config::Version::v1
);

our $VERSION = 1.0;

=head1 NAME

C<Cpanel::Config::ConfigObj::Interface::Config::v1>

=head1 SYNOPSIS

  package Cpanel::Config::ConfigObj::Driver::CustomModule;

  use Cpanel::Imports;

  use parent qw(
    Cpanel::Config::ConfigObj::Interface::Config::v1
  )

  sub info {

  }

  sub enable {

  }

  sub disable {

  }

  1;

=head1 DESCRIPTION

An interface to implement when you are setting up a component.

This interface provides a mechnism for users to render meta-data about a component
and enable/disable the component.

=cut

use constant {
    spec_version => 1,
};

=head1 STATIC METHODS

=head2 spec_actions()

Lis of predefined actions for a component

=cut

sub spec_actions {
    return {
        "info"    => "Print information about a feature.",
        "enable"  => "Set server configuration(s) of a feature to 'enabled'.",
        "disable" => "Set server configuration(s) of a feature to 'disabled'.",
    };
}

=head2 module_name($PACKAGE)

Helper to convert a Perl package to a module name.

=cut

sub module_name {
    my ($package) = @_;
    $package = ( ref $package ) ? ref $package : $package;
    my @package_pieces = split( '::', $package );
    return pop @package_pieces;
}

=head2 CLASS->base($DEFAULTS, $SOFTWARE)

Factory method to create a component provider.

=cut

sub base {
    my $class          = shift;
    my $class_defaults = shift || {};
    my $software_obj   = shift;

    if ( ref $class_defaults ne 'HASH' ) {
        $class_defaults = {};
    }

    my $default_settings = {
        'settings'      => {},
        'thirdparty_ns' => '',
        'args'          => {},
        'meta'          => {},
        'version'       => 1,
    };
    %{$default_settings} = ( %{$default_settings}, %{$class_defaults} );

    my $obj = $class->SUPER::new( $default_settings, $software_obj );

    return $obj;
}

=head2 CLASS->init($SOFTWARE)

Factory function to create a new component provider.

=cut

sub init {
    my ( $class, $software_obj ) = @_;

    my $defaults = {
        'settings'      => {},
        'thirdparty_ns' => '',
    };

    my $self = $class->base( $defaults, $software_obj );

    return $self;
}

=head1 PROPERTIES

=head2 INSTANCE->available_settings()

Get the named settings managed by the component provider.

=cut

sub available_settings {
    my ($self) = @_;
    return keys %{ $self->{'settings'} };
}

=head2 INSTANCE->run_thirdparty_function($MODULE, $FUNCTION, @ARGS)

Run a function in another module C<Cpanel::ThirdParty::$MODULE::$FUNCTION> as part
of this providers implemenation. The C<Cpanel::ThirdParty> namespace is provided
for third-party vendors to add their functionality to the system.

This routine allows us to run special thirdparty Perl not committed to cp/whm
idea being the vendor creates Software::$spec::$vendor.pm which can/will be
called dynamically by our utilities and UIs...if $vendor.pm needs access to
their custom Perl, this provides an interface to do so without any heavy
lifting on their part. caveat: their custom Perl must be in
C<Cpanel::ThirdParty::*>.  This avoids compile time dependencies in our
utilities for feature we ship in tarballs or expect to be available at
runtime

B<See Also:> C<run_thirdparty_method>
=cut

sub run_thirdparty_function {
    my ( $self, $module, $func, @args ) = @_;

    # honor the caller's wishes
    my $want_array = wantarray;

    $module =~ s/[^a-zA-Z0-9_\:]//g;
    die("Invalid module.") if !$module;

    $func =~ s/[^a-zA-Z0-9_]//g;
    die("Invalid function.") if !$func;

    my $fns = 'Cpanel::ThirdParty::' . $module;
    ( my $file = $fns ) =~ s/::/\//g;
    $file .= '.pm';
    if ( !$INC{$file} ) {
        eval "require $fns; 1;";    ## no critic qw(BuiltinFunctions::ProhibitStringyEval)
        if ( !$INC{$file} ) {
            Cpanel::Debug::log_warn("Failed to load ThirdParty Perl $fns.");
            return;
        }
    }
    my $task   = $fns . '::' . $func;
    my $subref = \&$task;
    my $result;
    eval {
        if ($want_array) {

            # assign as array, so callee may use wantarray as necessary
            @{$result} = $subref->(@args);
        }
        else {
            $result = $subref->(@args);
        }
        1;
    } or do {
        die( "Fail to execute ThirdParty code '$task': " . $@ );
    };

    return $want_array ? @{$result} : $result;
}

=head2 INSTANCE->run_thirdparty_method($MODULE, $FUNCTION, @ARGS)

Run a function in another module C<Cpanel::ThirdParty::$MODULE::$FUNCTION> as part
of this providers implemenation. The C<Cpanel::ThirdParty> namespace is provided
for third-party vendors to add their functionality to the system.

This just provide the class name to @args so methods like 'new' and 'init'
can be called. Don't expect anything crazy (ie method invocation via obj ref)

B<See Also:> C<run_thirdparty_function>
=cut

sub run_thirdparty_method {
    my ( $self, $module, $func, @args ) = @_;
    my $want_array = wantarray;

    $module =~ s/[^a-zA-Z0-9_\:]//g;
    die("Invalid module.") if !$module;

    $func =~ s/[^a-zA-Z0-9_]//g;
    die("Invalid method.") if !$func;

    my $fns = 'Cpanel::ThirdParty::' . $module;
    unshift @args, $fns;

    if ($want_array) {
        my @result = $self->run_thirdparty_function( $module, $func, @args );
        return @result;
    }

    return $self->run_thirdparty_function( $module, $func, @args );
}

=head2 INSTANCE->meta()

Getter for the meta data about this driver.

=cut

sub meta {
    my ($self) = @_;
    my $meta_obj = $self->interface()->fetch_meta_interface();

    $meta_obj->set_meta_content_from_driver($self);

    return $meta_obj;
}

=head1 SPECIFICATION MANDATED METHODS

All implementations must include the following methods.

=head2 INSTANCE->enable()

Enable the component. Must be overridden by defining class.

=cut

sub enable {
    return Cpanel::Debug::log_die( "'enable' must be implemented by subclasses of '" . __PACKAGE__ . "'" );
}

=head2 INSTANCE->disable()

Disable the component. Must be overridden by defining class.

=cut

sub disable {
    return Cpanel::Debug::log_die( "'disable' must be implemented by subclasses of '" . __PACKAGE__ . "'" );
}

=head1 SPECIFICATION MANDATED PROPERTIES

All implementations must include the following getters.

=head2 INSTANCE->info()

A short description of this component.

=cut

sub info { return shift->meta()->abstract(); }

=head1 OPTIONAL SPECIFICATION METHODS

=head2 INSTANCE->handle_showcase_submission()

Callback used to configure your component at the end of the feature showcase presentation.

=cut

use constant handle_showcase_submission => ();    #A no-op by default

=head2 INSTANCE->check()

Check if the component is enabled.

Defaults to off.

It's highly advised to implement the C<check> method in your custom provider
to provide the logic to decide if this component is enabled.
=cut

use constant check => 0;

=head2 INSTANCE->set_default()

Set the default
=cut

use constant set_default => undef;

=head2 INSTANCE->status()

This returns whether the feature is actually enabled.  For many features,
check already returns this value; however, while check returns whether the
feature *should* be enabled (i.e., whether we recommend it), this returns
whether the feature actually *is* enabled at the present moment.

=cut

sub status {
    my ($self) = @_;
    return $self->check;
}

1;
