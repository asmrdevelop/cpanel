#!/usr/bin/perl

# cpanel - bin/packman-apt.pl                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;
use JSON::PP ();    # JSON::PP was first released with perl v5.13.9

my $cache;

sub run {
    my ( $func, @args ) = @_;

    no strict "refs";
    print JSON::PP::encode_json( $func->(@args) );

    return 0;    # exit value
}

exit( run(@ARGV) ) unless caller;

###############
#### helpers ##
###############

my $load;

sub _get_cache_obj {

    $load ||= sub {

        # do once and not at compile time to avoid build system errors
        eval {

            # these are from libapt-pkg-perl
            require AptPkg::Config;
            require AptPkg::Cache;
        };
        die "Your system does not have the `libapt-pkg-perl` package. Please install it and try again.\n" if $@;
      }
      ->();

    $AptPkg::Config::_config->init;           # initialise the global config object with the default values and
    $AptPkg::Config::_config->system;         # setup the $_system object
    $AptPkg::Config::_config->{quiet} = 2;    # suppress cache building messages

    return AptPkg::Cache->new;
}

my $cached_index_files;                       # ¿TODO/YAGNI? disk based cache

sub _get_index_file_hr {
    my ( $file, $pkg ) = @_;

    if ( !exists $cached_index_files->{$file} ) {
        my $line;    # buffer
        my $cur_pkg;
        my $cur_key;
        my $val;
        my %result;
        open( my $fh, "<", $file ) or die "Could not read “$file”: $!\n";

        while ( $line = <$fh> ) {
            chomp $line;
            next if !length($line);

            if ( $line =~ m/^Package:\s+(\S+)/ ) {
                $cur_pkg = $1;
                if ( exists $result{$cur_pkg} ) {
                    warn "Package “$cur_pkg” is in debian index more than once\n" if substr( $cur_pkg, 0, 3 ) eq "ea-";
                }

                $result{$cur_pkg} = undef;
            }
            else {
                if ( $line =~ m/^\s/ ) {
                    warn "Multiline data detected prior to key line (Pkg: $cur_pkg Line: -$line-)\n" if !length($cur_key);
                    $result{$cur_pkg}{$cur_key} .= "\n$line";
                }
                elsif ( $line =~ m/^[-\w]+:(\s+)/ ) {
                    my $ws = $1;
                    ( $cur_key, $val ) = split( ":$ws", $line, 2 );
                    $result{$cur_pkg}{$cur_key} = $val;
                }
            }

        }

        close $fh;

        $cached_index_files->{$file} = \%result;
    }

    return $cached_index_files->{$file}{$pkg};
}

################
#### commands ##
################

sub pkg_state_hr {
    my @pkgs = @_;

    $cache //= _get_cache_obj();
    my $policy = $cache->policy;

    my %state;
    for my $pack (@pkgs) {
        my $p = $cache->{$pack};
        next if !$p;
        next if $p->{ProvidesList};    # skip virtual pkgs

        my $version_latest;
        if ( my $c = $policy->candidate($p) ) {
            $version_latest = $c->{VerStr};
        }
        else {
            # somehow it is in the cache but there are no actual packages available
            next;
        }

        my $version_installed = $p->{CurrentVer} ? $p->{CurrentVer}{VerStr} : undef;

        if ($version_installed) {
            $state{$pack} = $version_installed eq $version_latest ? 'installed' : 'updatable';
        }
        else {
            $state{$pack} = 'not_installed';
        }
    }

    return \%state;
}

sub all_pkgs {
    $cache //= _get_cache_obj();
    my $policy = $cache->policy;

    my %seen;
    my @pkgs;
    for my $pkg ( keys %{$cache} ) {
        my $p = $cache->{$pkg};
        next if !$p;
        next if $p->{ProvidesList};         # skip virtual pkgs
        next if !$policy->candidate($p);    # somehow it is in the cache but there are no actual packages available

        my $offset = index( $pkg, ":" );
        if ( $offset > -1 ) {
            $pkg = substr( $pkg, 0, $offset );
        }
        $seen{$pkg}++;
        push @pkgs, $pkg if $seen{$pkg} == 1;
    }

    return \@pkgs;
}

sub pkg_info {    ## no critic qw(Subroutines::ProhibitExcessComplexity)
    my @pkgs = @_;

    $cache //= _get_cache_obj();
    my $policy = $cache->policy;

    my @pkg_info;
    for my $pack (@pkgs) {
        my $p = $cache->{$pack};
        next if !$p;

        if ( my $pn = $p->{ProvidesList} ) {
            my %seen;
            my $virt_hr = { is_virtual => 1, package => $pack };
            $virt_hr->{provided_by}       = [ map { $seen{ $_->{OwnerPkg}{Name} }++ == 0 ? $_->{OwnerPkg}{Name} : () } @{$pn} ];
            $virt_hr->{version_installed} = $p->{CurrentVer}{VerStr} if $p->{CurrentVer};
            push @pkg_info, $virt_hr;
            next;
        }

        my $res_hr = { Package => $pack, Architecture => $p->{Arch}, Section => $p->{Section} };
        $res_hr->{version_installed} = $p->{CurrentVer}{VerStr} if $p->{CurrentVer};

        if ( my $c = $policy->candidate($p) ) {
            $res_hr->{version_latest} = $c->{VerStr};
            $res_hr->{Version}        = $c->{VerStr};
        }
        else {
            # somehow it is in the cache but there are no actual packages available
            next;
        }

        if ( $res_hr->{version_installed} ) {
            $res_hr->{state} = $res_hr->{version_installed} eq $res_hr->{version_latest} ? 'installed' : 'updatable';
        }
        else {
            $res_hr->{state} = 'not_installed';
        }

        if ( my $available = $p->{VersionList} ) {
            my $v = $available->[0];         # only care about 1st (@$available)
            $res_hr->{Size} = $v->{Size};    # or ¿ $idx_pkg_hr->{"Installed-Size"} ?

          AVAIL:
            for my $avlb ( @{$available} ) {
              FILE:
                for my $file ( @{ $avlb->{FileList} } ) {
                    my $filobj = $file->{File};
                    if ( $filobj->{IndexType} eq 'Debian Package Index' ) {
                        $res_hr->{"APT-Sources"} = "$filobj->{Label} @ $filobj->{Site}";

                        $res_hr->{debian_index_file} = $filobj->{FileName};
                        if ( my $idx_pkg_hr = _get_index_file_hr( $res_hr->{debian_index_file} => $pack ) ) {
                            for my $key (qw(Description Homepage Maintainer)) {
                                $res_hr->{$key} = $idx_pkg_hr->{$key} if exists $idx_pkg_hr->{$key};
                            }
                        }

                        last AVAIL;
                    }
                }
            }

            # in case we found no debian index
            for my $key (qw(Homepage Maintainer)) {
                $res_hr->{$key} ||= "Unknown";
            }

            if ( my $deps = $v->{DependsList} ) {
                my $type  = '';
                my $delim = '';
                for my $d (@$deps) {
                    my $exp_key = "$d->{DepType}_with_virtual_packages_expanded";
                    $res_hr->{$exp_key} //= [];
                    $res_hr->{ $d->{DepType} } .= $delim if $type eq $d->{DepType} && exists $res_hr->{ $d->{DepType} };
                    $type  = $d->{DepType};
                    $delim = ( $d->{CompType} & AptPkg::Dep::Or() ) ? ' | ' : ', ';
                    $res_hr->{ $d->{DepType} } .= $d->{TargetPkg}{ShortName};
                    $res_hr->{ $d->{DepType} } .= " ($d->{CompTypeDeb} $d->{TargetVer})" if $d->{TargetVer};

                    if ( my $vpkgs = $d->{TargetPkg}{ProvidesList} ) {
                        my %seen;
                        if ( $d->{DepType} eq "Conflicts" ) {

                            # do not include the virtual package itself, $d->{TargetPkg}{ShortName}
                            #    or else resolution will barf about unmet deps since it doesn’t actually exist
                            push @{ $res_hr->{$exp_key} }, map { $_->{OwnerPkg}{ShortName} ne $pack && $seen{ $_->{OwnerPkg}{ShortName} }++ == 0 ? $_->{OwnerPkg}{ShortName} : () } @{$vpkgs};
                        }
                        else {
                            my @providers = map { $seen{ $_->{OwnerPkg}{ShortName} }++ == 0 ? $_->{OwnerPkg}{ShortName} : () } @{$vpkgs};
                            push @{ $res_hr->{$exp_key} }, @providers == 1 ? $providers[0] : \@providers;
                        }
                    }
                    else {
                        push @{ $res_hr->{$exp_key} }, $d->{TargetPkg}{ShortName};
                    }
                }
            }

            if ( my $p = $v->{ProvidesList} ) {
                $res_hr->{Provides} = join ', ', map { $_->{Name} } @{$p};
            }
        }

        push @pkg_info, $res_hr;
    }

    return \@pkg_info;
}
