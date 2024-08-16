package Cpanel::PackMan::DepSolver;

# cpanel - Cpanel/PackMan/DepSolver.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::Exception ();

# TODO: POD

sub new {
    my ( $class, %OPTS ) = @_;

    foreach my $required (qw(packages_wanted_in_namespaces package_map package_states)) {
        die Cpanel::Exception::create( 'MissingParameter', [ 'name' => $required ] ) if !$OPTS{$required};
    }

    my $packages_wanted_in_namespaces_ref = $OPTS{'packages_wanted_in_namespaces'};    # hashref package => 1 , ....
    my $package_map_ref                   = $OPTS{'package_map'};                      # Data from get_multi_info maped to a hash
    my $package_states_ref                = $OPTS{'package_states'};                   # Packages by 'installed','not_installed','updatable'
    my $namespaces                        = $OPTS{'namespaces'};                       # support multiple namespaces

    my %packages_not_wanted_in_namespaces = map { $packages_wanted_in_namespaces_ref->{$_} ? () : ( $_ => 1 ) } keys %{$package_map_ref};

    my $self = {
        'packages_wanted_in_namespaces'     => $packages_wanted_in_namespaces_ref,
        'packages_not_wanted_in_namespaces' => \%packages_not_wanted_in_namespaces,
        'namespaces'                        => $namespaces,
        'package_states'                    => $package_states_ref,
        'package_map'                       => $package_map_ref,
    };

    return bless $self, $class;
}

sub solve_deps {
    my ($self) = @_;

    $self->{'deps'} = {
        'wanted'     => { map { $_ => 1 } keys %{ $self->{'packages_wanted_in_namespaces'} } },
        'not_wanted' => { map { $_ => 1 } keys %{ $self->{'packages_not_wanted_in_namespaces'} } },
        'conflicts'  => {},
        'required'   => {},
    };

    # ORDER MATTERS!
    $self->{'packages_that_need_deps_solved'} = [ sort keys %{ $self->{'packages_wanted_in_namespaces'} } ];
    $self->{'packages_with_deps_solved'}      = {};
    $self->{'packages_with_conflicts_set'}    = {};

    # Preload all conflicts
    foreach my $package_name ( keys %{ $self->{'deps'}{'wanted'} } ) {
        $self->{'packages_with_conflicts_set'}{$package_name} = 1;
        my $pkg_dep = $self->{'package_map'}{$package_name}{'pkg_dep'} or next;
        foreach my $conflict_package ( @{ $pkg_dep->{'conflicts'} } ) {
            $self->_set_package_conflict( $conflict_package, 'conflict' );
        }
    }

    while ( @{ $self->{'packages_that_need_deps_solved'} } ) {
        my $package_name = shift @{ $self->{'packages_that_need_deps_solved'} };

        next if $self->{'packages_with_deps_solved'}{$package_name};    #already solved
        $self->{'packages_with_deps_solved'}{$package_name} = 1;

        my $pkg_dep = $self->{'package_map'}{$package_name}{'pkg_dep'} or next;

        # Process conflicts first
        if ( !$self->{'packages_with_conflicts_set'}{$package_name} ) {
            foreach my $conflict_package ( @{ $pkg_dep->{'conflicts'} } ) {
                $self->_set_package_conflict( $conflict_package, 'conflict' );
            }
            $self->{'packages_with_conflicts_set'}{$package_name} = 1;
        }

        # Process requires second
        foreach my $required_package ( @{ $pkg_dep->{'requires'} } ) {
            if ( ref $required_package ) {
                $self->_process_at_least_one_provider($required_package);
            }
            else {
                $self->_set_package_required($required_package);
            }
        }

    }

    return $self->{'deps'};
}

sub _set_package_conflict {
    my ( $self, $conflict_package ) = @_;
    my $deps = $self->{'deps'};
    $deps->{'conflicts'}{$conflict_package}  = 1;
    $deps->{'not_wanted'}{$conflict_package} = 1;
    delete $deps->{'wanted'}{$conflict_package};
    $self->{'packages_with_deps_solved'}{$conflict_package} = 1;
    return 1;
}

sub _set_package_required {
    my ( $self, $required_package ) = @_;

    my $deps = $self->{'deps'};
    $deps->{'required'}{$required_package} = 1;
    $deps->{'wanted'}{$required_package}   = 1;
    delete $deps->{'not_wanted'}{$required_package};

    if ( !$self->{'packages_with_deps_solved'}{$required_package} ) {

        # Be sure to solve this one next as we need to collect conflicts right away
        # ORDER MATTERS!
        unshift @{ $self->{'packages_that_need_deps_solved'} }, $required_package;
    }
    return 1;
}

sub _process_at_least_one_provider {
    my ( $self, $required_at_least_one_of ) = @_;

    my $deps = $self->{'deps'};

    # If we can fill the require with one the packages we have asked
    # to install try that first
    foreach my $potential_provider (@$required_at_least_one_of) {

        if ( $deps->{'wanted'}{$potential_provider} ) {
            $self->_set_package_required($potential_provider);
            return;
        }
    }

    # If we failed to fill the require we look to see
    # if anything we already have installed will fill and
    # and we keep that

    foreach my $potential_provider (@$required_at_least_one_of) {

        if ( $self->{'package_states'}{$potential_provider}
            && ( $self->{'package_states'}{$potential_provider} eq 'installed' || $self->{'package_states'}{$potential_provider} eq 'updatable' ) ) {
            $self->_set_package_required($potential_provider);
            return;
        }
    }

    # If we failed to fill the require we look to see
    # if anything in the namespace can fill it
    foreach my $namespace ( @{ $self->{'namespaces'} } ) {
        my $prefix        = "$namespace-";
        my $prefix_length = length $prefix;
        foreach my $potential_provider (@$required_at_least_one_of) {
            if ( substr( $potential_provider, 0, $prefix_length ) eq $prefix ) {
                $self->_set_package_required($potential_provider);
                return;
            }
        }
    }

    # Finally we just try to fill it with the first provider
    # in the list
    my $first_dep_provider = $required_at_least_one_of->[0];
    $self->_set_package_required($first_dep_provider);

    return 1;
}

1;
__END__
