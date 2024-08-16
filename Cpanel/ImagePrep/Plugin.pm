
# cpanel - Cpanel/ImagePrep/Plugin.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::ImagePrep::Plugin;

use cPstrict;
use Carp         ();
use Cpanel::JSON ();

use parent 'Cpanel::ImagePrep::Task';

=head1 NAME

Cpanel::ImagePrep::Plugin

=head1 DESCRIPTION

A plugin system for the snapshot_prep and post_snapshot utilities.
This allows flexibility for packages that may store per-instance
data on disk in a way that needs cleaning before and/or after
creating a VM image but are not built-in parts of cPanel & WHM.
The pre- and post-snapshot routines need not be shipped with
cPanel & WHM but rather can be added in by separate software
packages and implemented in any language.

=head1 CREATING A PLUGIN

The installer for your plugin file should pre-create the
/var/cpanel/snapshot_prep.d directory with 755 permissions if it doesn't
already exist.

Then it creates a JSON file (e.g., myplugin.json) in /var/cpanel/snapshot_prep.d
to represent your plugin. You can read our snapshot_prep and post_snapshot
plugin documentation go.cpanel.net/snapshotplugin for a complete guide on
how to do this.

=head1 TASK DEPENDENCIES

Currently, all plugin tasks are dependent on the C<ipaddr_and_hostname>, C<mysql>,
and C<cpwhm_misc> tasks. The ability to customize this dependency list for plugins
may be added in the future if needed.

You cannot make built-in tasks depend on your plugin task, but you may choose
to skip existing tasks altogether in favor of an alternative implementation.

=head1 FUNCTIONS

=head2 Main interface is the same as C<Cpanel::ImagePrep::Task>

See C<Cpanel::ImagePrep::Task> for the methods that are available.

The rest below is specific to C<Cpanel::ImagePrep::Plugin>.

=head2 new()

Unused - see C<load()>

=cut

sub new {
    Carp::croak('use load(), not new()');
}

=head2 load($plugin_path)

Load the plugin from $plugin_path (an absolute path to a JSON file on disk).
Returns an object with the same interface as c<Cpanel::ImagePrep::Task>.

=cut

sub load {
    my ( $package, $path ) = @_;
    my $plugin_data = Cpanel::JSON::LoadFile($path);    # If it fails this early, we should abort the entire run instead of just marking it as a task failure

    my $self = { _plugin_file => $path };
    for my $attribute (qw(name type pre post description)) {
        $self->{$attribute} = delete( $plugin_data->{$attribute} ) || die "ERROR: The plugin '$path' must include a '$attribute' attribute.\n";
    }

    # optional attributes
    for my $attribute (qw(deps before)) {
        next unless exists $plugin_data->{$attribute};
        $self->{$attribute} = delete( $plugin_data->{$attribute} );
    }

    if ( $self->{name} !~ /^[a-zA-Z0-9_]+$/ ) {
        die "ERROR: The plugin name '$self->{name}' is not valid. You can only use a-zA-Z0-9_ in the name.\n";
    }
    my $plugin_class = sprintf( 'Cpanel::ImagePrep::Plugin::%s', $self->{name} );
    eval "package $plugin_class;\nuse parent '$package';\n";    ##no critic(ProhibitStringyEval)
    bless $self, $plugin_class;

    $self->_validate_plugin_attributes;

    return $self;
}

sub _description {
    my ($self) = @_;
    return $self->{description};
}

sub _type {
    my ($self) = @_;
    return $self->{type};
}

sub _pre {
    my ($self) = @_;

    $self->loginfo( sprintf( 'Running plugin task %s pre stage', $self->{_plugin_file} ) );
    $self->common->run_command( @{ $self->{pre} } );
    return $self->PRE_POST_OK;
}

sub _post {
    my ($self) = @_;

    $self->loginfo( sprintf( 'Running plugin task %s post stage', $self->{_plugin_file} ) );
    $self->common->run_command( @{ $self->{post} } );
    return $self->PRE_POST_OK;
}

=head2 is_plugin()

Always returns 1. This is to distinguish plugin objects from non-plugin Task objects.

=cut

sub is_plugin {
    return 1;
}

sub _validate_plugin_attributes {
    my ($self) = @_;
    my $plugin_file = $self->{_plugin_file};

    die "ERROR: [$plugin_file] Plugin tasks are not allowed to perform repairs\n" if $self->{type} ne 'non-repair only';

    for my $array_attribute (qw(pre post deps before)) {
        next unless exists $self->{$array_attribute};
        ref $self->{$array_attribute} eq 'ARRAY' or die "ERROR: [$plugin_file] The '$array_attribute' attribute must be an array.\n";
    }

    for my $attribute (qw(pre post)) {
        next unless exists $self->{$attribute};
        my $exec_path = $self->{$attribute}[0] // q{};
        if ( !length $exec_path || !-f $exec_path || !-x _ ) {
            die "ERROR: [$plugin_file] The '$attribute' attribute must contain an absolute path to a program that exists and is executable.\n";
        }
    }

    return;
}

sub _deps {
    my ($self) = @_;
    return @{ $self->{'deps'} || [qw(ipaddr_and_hostname mysql cpwhm_misc)] };    # A best guess for now about what plugins will need
}

sub _before {
    my ($self) = @_;
    return @{ $self->{'before'} || [] };
}

1;
