package Whostmgr::Limits::PackageLimits;

# cpanel - Whostmgr/Limits/PackageLimits.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
#NOTE: This file is a circular dependency with Whostmgr/Limits.pm.
#----------------------------------------------------------------------

use strict;
use Cpanel::CachedDataStore  ();
use Cpanel::ConfigFiles      ();
use Whostmgr::Limits::Config ();

#PACKAGENAME:
#  LIMIT:
#    LIMITTYPE:
#      USER: LIMITVALUE

sub load {
    my ( $class, $lock, $opt_fname ) = @_;

    # Usage is safe as we own /var/cpanel and the dir
    $opt_fname = $Whostmgr::Limits::Config::PACKAGE_LIMITS_FILE unless ( defined $opt_fname );
    my $package_limits = Cpanel::CachedDataStore::loaddatastore( $opt_fname, $lock );

    if ( !$package_limits->{'data'} ) {
        $package_limits->{'data'} = {};
    }

    bless( $package_limits, $class );
    return $package_limits;
}

sub list_packages {
    my ($package_limits) = @_;
    my @keys = keys %{ $package_limits->{'data'} };
    return \@keys;
}

## returns 1 if the $pkg_name is deleted from $package_limits
sub cleanup_package {
    my ( $package_limits, $pkg_name ) = @_;
    if ( !-e "$Cpanel::ConfigFiles::PACKAGES_DIR/$pkg_name" ) {

        # Remove unused package specifications
        delete $package_limits->{'data'}{$pkg_name};
        return 1;
    }

    ## the only current value for $LIMIT is 'allowed'
    foreach my $LIMIT ( keys %{ $package_limits->{'data'}->{$pkg_name} } ) {
        my $hr_limit = $package_limits->{'data'}{$pkg_name}{$LIMIT};
        foreach my $LIMITTYPE ( keys %$hr_limit ) {
            unless ( ( scalar keys %{ $hr_limit->{$LIMITTYPE} } ) ) {
                ## If the package limit type key is empty remove it from the reference
                ## e.g., the package has 'create: {}' or 'number: {}' in its .yaml entry
                delete $hr_limit->{$LIMITTYPE};
            }
        }

        ## accounts for Whostmgr::Limits::Config, which used to delete 'create' but leave the 'number' hash
        unless ( exists $hr_limit->{'create'} ) {
            delete $package_limits->{'data'}{$pkg_name};
            return 1;
        }

        unless ( scalar keys %{ $package_limits->{'data'}->{$pkg_name}->{$LIMIT} } ) {
            ## If the package limit key is empty remove it from the reference
            ## e.g., both 'create' and 'number' are empty, so delete 'allowed'
            delete $package_limits->{'data'}{$pkg_name}->{$LIMIT};
        }
    }

    unless ( scalar keys %{ $package_limits->{'data'}{$pkg_name} } ) {
        ## If the package is empty remove it from the reference
        delete $package_limits->{'data'}{$pkg_name};
        return 1;
    }

    return 0;
}

#TODO: Have this report failures
sub save {
    my ( $package_limits, $opt_fname ) = @_;
    my $fname = defined $opt_fname ? $opt_fname : $Whostmgr::Limits::Config::PACKAGE_LIMITS_FILE;

    # Usage is safe as we own /var/cpanel and the dir
    Cpanel::CachedDataStore::savedatastore( $fname, $package_limits );
    return;
}

# Gets/sets whether or not a reseller can create accounts using a given package
sub create_for_reseller {
    my ( $package_limits, $pkg_name, $reseller, $opt_set ) = @_;
    if ( defined $opt_set ) {
        $package_limits->{'data'}{$pkg_name}{'allowed'}{'create'}{$reseller} = $opt_set;
    }
    return $package_limits->{'data'}{$pkg_name}{'allowed'}{'create'}{$reseller};
}

# Gets/sets the number of accounts a reseller can create for a given package
sub number_for_reseller {
    my ( $package_limits, $pkg_name, $reseller, $opt_set ) = @_;
    if ( defined $opt_set ) {
        $package_limits->{'data'}{$pkg_name}{'allowed'}{'number'}{$reseller} = $opt_set;
    }
    return $package_limits->{'data'}{$pkg_name}{'allowed'}{'number'}{$reseller};
}

# Removes the ability for a reseller to create accounts for a given package
sub delete_reseller {
    my ( $package_limits, $pkg_name, $reseller ) = @_;
    delete $package_limits->{'data'}{$pkg_name}{'allowed'}{'create'}{$reseller};
    delete $package_limits->{'data'}{$pkg_name}{'allowed'}{'number'}{$reseller};
    ## TODO?: call packagelimits_cleanup_package
    return;
}

## grab package limits by reseller
sub load_by_reseller {
    my ( $class, $reseller ) = @_;

    my $package_limits = $class->load();
    my $user_package_limits;

    my $ar_pkg_names = $package_limits->list_packages();

    # Only store limits that affect us and remove any limits that are empty after we pull outselves out
    for my $pkg_name (@$ar_pkg_names) {
        foreach my $LIMIT ( keys %{ $package_limits->{'data'}{$pkg_name} } ) {
            foreach my $LIMITTYPE ( keys %{ $package_limits->{'data'}{$pkg_name}{$LIMIT} } ) {
                foreach my $USER ( keys %{ $package_limits->{'data'}{$pkg_name}{$LIMIT}{$LIMITTYPE} } ) {
                    if ( $USER eq $reseller ) {
                        $user_package_limits->{'data'}{$pkg_name}{$LIMIT}{$LIMITTYPE}{$USER} = $package_limits->{'data'}{$pkg_name}{$LIMIT}{$LIMITTYPE}{$USER};
                    }
                }
            }
        }
    }
    if ( $user_package_limits && ref $user_package_limits eq 'HASH' ) {
        bless( $user_package_limits, $class );
        return $user_package_limits;
    }
    else {
        return;
    }
}

sub change_reseller {
    my ( $reseller, $newreseller ) = @_;

    my $package_limits = Whostmgr::Limits::PackageLimits->load(1);

    my $ar_pkg_names = $package_limits->list_packages();

    # Only store limits that affect us and remove any limits that are empty after we pull outselves out
    for my $pkg_name (@$ar_pkg_names) {
        foreach my $LIMIT ( keys %{ $package_limits->{'data'}{$pkg_name} } ) {
            foreach my $LIMITTYPE ( keys %{ $package_limits->{'data'}{$pkg_name}{$LIMIT} } ) {
                foreach my $USER ( keys %{ $package_limits->{'data'}{$pkg_name}{$LIMIT}{$LIMITTYPE} } ) {
                    if ( $USER eq $reseller ) {
                        $package_limits->{'data'}{$pkg_name}{$LIMIT}{$LIMITTYPE}{$newreseller} = $package_limits->{'data'}{$pkg_name}{$LIMIT}{$LIMITTYPE}{$USER};
                        delete $package_limits->{'data'}{$pkg_name}{$LIMIT}{$LIMITTYPE}{$USER};
                    }
                }
            }
        }
        my $new_pkg_name = $pkg_name;
        if ( $new_pkg_name =~ s/^\Q$reseller\E_/$newreseller\_/g ) {
            if ( $package_limits->{'data'}{$new_pkg_name} = $package_limits->{'data'}{$pkg_name} ) {
                delete $package_limits->{'data'}{$pkg_name};
            }
        }
    }

    $package_limits->save();
    return;
}

sub cleanup {
    my ($package_limits) = @_;
    my $ar_pkg_names = $package_limits->list_packages();
    foreach my $pkg_name (@$ar_pkg_names) {
        $package_limits->cleanup_package($pkg_name);
    }
    return;
}

1;
