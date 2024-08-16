package Cpanel::Init::Services;

# cpanel - Cpanel/Init/Services.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Moo;
use cPstrict;

use Algorithm::Dependency::Ordered;
use Algorithm::Dependency::Source::HoA;
use Cpanel::Init::Utils;
use Text::Abbrev;
use Carp;

has 'services' => ( is => 'rw' );
has 'dep_tree' => ( is => 'rw' );

sub BUILD {
    my ( $self, $params ) = @_;

    if ( $params->{'services'}
        && ( ref $params->{'services'} eq 'HASH' ) ) {
        $self->services( $params->{'services'} );
    }
    else {
        $self->services(Cpanel::Init::Utils::merge_services);
    }

    return $self->build_tree;
}

sub build_tree {
    my ($self) = @_;

    $self->check_yaml;

    my $services = $self->services;

    my $source   = Algorithm::Dependency::Source::HoA->new($services);
    my $dep_tree = Algorithm::Dependency::Ordered->new( 'source' => $source );

    croak("Unable to build dependency tree\n") unless ref $dep_tree;

    $self->dep_tree($dep_tree);

    return;
}

sub all {
    my ($self) = @_;
    return $self->dep_tree->schedule_all;
}

sub dependencies_for {
    my ( $self, $service ) = @_;
    my $dep = $self->dep_tree;

    return $dep->depends($service);
}

sub add {
    my ( $self, $service, $dependencies ) = @_;
    $dependencies ||= [];

    if ( !exists $self->services->{$service} ) {
        $self->services->{$service} = $dependencies;
        Cpanel::Init::Utils::write_services( $self->services );
        $self->build_tree;
    }
    if ( $self->valid_service($service) ) {
        return 1;
    }
    return 0;
}

sub remove {
    my ( $self, $service ) = @_;

    if ( exists $self->services->{$service} ) {
        delete $self->services->{$service};
        Cpanel::Init::Utils::write_services( $self->services );
        $self->build_tree;
        if ( !$self->valid_service($service) ) {
            return 1;
        }
        return 0;
    }
}

sub valid_service {
    my ( $self, $service ) = @_;

    $service =~ s/\.sh$//;

    my $services = $self->all;

    # Create abbreviation table
    my $abbrev_hash = abbrev @{$services};
    return ( exists $abbrev_hash->{$service} ) ? $abbrev_hash->{$service} : '';
}

sub check_yaml {
    my ($self) = @_;

    my $errors = Cpanel::Init::Utils::check_services_yaml( $self->services );

    if ($errors) {
        print 'Errors in /var/cpanel/cpservices.yaml' . "\n";
        foreach my $key ( keys %{$errors} ) {
            if ( exists $errors->{$key} and $key eq 'no_service' ) {
                foreach my $error ( @{ $errors->{$key} } ) {
                    print "\t" . 'The service \'' . $error . '\' is used as a dependency but it is not a service. It maybe misspelled.' . "
\n";
                }
            }
            if ( exists $errors->{$key} and $key eq 'resursive_dep' ) {
                foreach my $error ( keys %{ $errors->{$key} } ) {
                    print "\t" . $error . ' has a circular depenency with ' . $errors->{$key}{$error} . ".\n";
                }
            }
        }
        _exit();
    }

    return;
}

sub _exit { exit }    ## no critic(Cpanel::NoExitsFromSubroutines)

1;

__END__

=head1 NAME

Cpanel::Init::Services - [All services and their dependencies]

=head1 SYNOPSIS

    use Cpanel::Init::Services;

    my $dependency_tree = {
        'clamd'           => [],
        'cpanellogd'      => [],
    };

    my $services = Cpanel::Init::Services->new({services => $dependency_tree});

    $services->add('ssl-something', [qw{clamd cpanellogd ircd}]);
    $dependencies = $services->dependencies_for('ssl-something');

    $services->add('ircd');
    $services->remove('ssl-something');

    my $all = $services->all;

=head1 DESCRIPTION

    Cpanel::Init::Services represents all the services cPanel supports for init. If
    a initscript has dependencies they will be Hash of Array data structure found above.

=head1 PRIVATE INTERFACE

=head2 Methods

=over 4

=item build_tree

Argument list: { service_name => [qw{ dependency list }] }

This method takes the argument of an array of hashes and builds a new Algorithm::Dependency::Ordered
object that is an attribute of the class.

=back

=head1 PUBLIC INTERFACE

=head2 Methods

=over 4

=item new

Argument list: { service_name => [qw{ dependency list }] }

=item all

This method will return an array reference of services in a order that will satisfy
all dependencies.

=item dependencies_for

Argument list: $service

This method will take a service name and return an array reference of the services
that will satisfy that services. The last item in the array reference is the service
name that was passed in to the method.

=item add

Argument list: $service_name, [qw{ dependency list }]

This method adds a new service to the dependency tree. Optionally, you can pass a
list of dependencies. The dependencies must already exists in the tree or the function will fail.

=item remove

Argument list: $service_name

This method removes a service from the dependency tree.

=back
