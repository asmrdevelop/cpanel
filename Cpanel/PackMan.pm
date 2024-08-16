package Cpanel::PackMan;

# cpanel - Cpanel/PackMan.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use File::Temp;
use Moo;
use cPstrict;    # must be after Moo

use Cpanel::Rlimit           ();
use Cpanel::Time::Local      ();
use Cpanel::FileUtils::Write ();
use Cpanel::SafeDir::MK      ();
use Cpanel::OS               ();

our $_LOGS_BASE = '/usr/local/cpanel/logs';

if ( $INC{'B/C.pm'} ) {

    # see  https://rt.cpan.org/Ticket/Display.html?id=104854 is addressed.
    my ( $pkg, $file, $line ) = caller();
    die("Cpanel::PackMan must not be loaded at compile time at $file line $line\n");
}

our $VERSION = "0.02";

with 'Role::Multiton';

has type => (
    is      => "ro",
    isa     => sub { die "Must be 'ea4' or 'packman'\n" if $_[0] ne 'ea4' && $_[0] ne 'packman' },
    default => "packman",
);

has build => (
    is       => 'rw',
    isa      => sub { die "Needs to be Cpanel::PackMan::Build based\n" if !$_[0]->isa('Cpanel::PackMan::Build') },
    lazy     => 1,
    init_arg => undef,
    default  => sub {
        my ($self) = @_;    # safe because it can't be be fired during new because it is init_arg => undef

        require Cpanel::PackMan::Build;
        my $dir = "$_LOGS_BASE/" . $self->type;
        mkdir( $dir, 0700 );                                           # just try
        return Cpanel::PackMan::Build->instance( log_dir => $dir );    # safe because it can't be be fired during new because it is init_arg => undef
    },
);

has sys => (
    is       => 'rw',
    isa      => sub { die "Needs to be Cpanel::PackMan::Sys based\n" if !$_[0]->isa('Cpanel::PackMan::Sys') },
    lazy     => 1,
    init_arg => undef,
    default  => sub {
        my $package_manager = Cpanel::OS::package_manager();
        my $ns              = "Cpanel::PackMan::Sys::$package_manager";

        require Cpanel::LoadModule;
        eval { Cpanel::LoadModule::load_perl_module($ns) };
        die "Failed to load “$package_manager” implementation for “" . Cpanel::OS::display_name() . "”:\n\t$@\n" if $@;

        return $ns->new;
    },
);

has logger => (
    is       => "rw",
    isa      => sub { die "Needs to be Cpanel::Logger based\n" if !$_[0]->isa('Cpanel::Logger') },
    lazy     => 1,
    init_arg => undef,
    default  => sub {
        require Cpanel::Logger;
        return Cpanel::Logger->new;
    },
);

sub is_installed ( $self, $pkg_hr ) {
    $pkg_hr = $self->pkg_hr($pkg_hr) if !ref($pkg_hr);
    return $pkg_hr                   if $pkg_hr->{version_installed};
    return;
}

sub is_uptodate ( $self, $pkg_hr ) {
    $pkg_hr = $self->pkg_hr($pkg_hr) if !ref($pkg_hr);
    return                           if !ref($pkg_hr);                                               # not installed!
    return                           if !$self->is_installed($pkg_hr);
    return $pkg_hr                   if $pkg_hr->{version_installed} eq $pkg_hr->{version_latest};
    return;
}

sub multi_op ( $self, $ops ) {
    my ( $tmp_fh, $tmp_file ) = File::Temp::tempfile( CLEANUP => 1 );

    my $cnt = 0;
    for my $action (qw(uninstall upgrade install)) {
        next if !exists $ops->{$action};
        next if !@{ $ops->{$action} };
        $cnt++;
        print {$tmp_fh} join( " ", ( $action, @{ $ops->{$action} } ) ) . "\n";
    }
    close($tmp_fh);

    # If we process at least one command, run them and parse the output
    if ($cnt) {
        my @shell_output;
        my $line_handler = sub { my $out = $_[0]; chomp($out); push( @shell_output, $out ) if $out; $self->logger->info($out) if $out; return ''; };
        my @shell_args   = $self->sys->syscmd_args_txn($tmp_file);

        $self->sys->syscmd( $line_handler, @shell_args );
        $self->_parse_for_errors( \@shell_output );

        return $cnt;
    }

    # There was nothing to do here..
    return 0;
}

sub resolve_multi_op ( $self, $pkgs_want_ar = [], $ns = undef, $die_if_unavailable = 0 ) {    ## no critic qw(Subroutines::ProhibitExcessComplexity Subroutines::ProhibitManyArgs)

    # We need to free ourselves from the memory restrictions here to avoid the following error (seen after some time) running deplist
    #   Fatal Python error: Couldn't create autoTLSkey mapping
    my $limits_hr = Cpanel::Rlimit::get_current_rlimits();
    Cpanel::Rlimit::set_rlimit_to_infinity();

    my %pkgs_to_install;

    foreach my $p ( @{$pkgs_want_ar} ) {
        $pkgs_to_install{$p} = 1;
    }

    my @pkgs_have;
    my %pkgs_have_lu;
    @pkgs_have_lu{@pkgs_have} = ();

    my @do_not_remove;
    if ( defined $ns ) {

        if ( $ns eq 'ea' ) {
            $pkgs_to_install{'ea-profiles-cpanel'} = 1;
            @pkgs_have                             = grep { substr( $_, 0, 3 ) eq "ea-" && $_ ne "ea-profiles-cpanel" } $self->list( state => "installed" );
            @do_not_remove                         = ("ea-profiles-cpanel");
        }
        else {
            if ( $ns !~ m/^[a-z][a-z0-9]+$/ ) {
                die "Namespace must start with a letter, be at least two characters long, and only contain ascii a-z0-9\n";
            }

            if ( !-f "/etc/cpanel/ea4/additional-pkg-prefixes/$ns" ) {
                die "Unknown namespace “$ns” given.\n";
            }
        }
    }

    # else die No ns given? only if it wants to uninstall tons of stuff TEST/VERIFY before committting!!!!!!

    #####################
    #### BEGIN LOGIQUE ##
    #####################

    my %_ts_data = ();

    ###############################################################
    #### Step 1: Determine dependencies for the packages we want to install two levels deep
    ####-------- Pass 1: Determine the dependencies of all the packages we are explicitly installing
    ####-------- Pass 2: Determine the dependencies of the dependencies, giving us two levels of resolution.
    ####                 * There may be cases in the future where more are needed, but unforseeable at this time
    ###############################################################
    my $pkgref                                          = $self->multi_pkg_info( 'prefixes' => [ $ns || '' ] );
    my %pkg_states                                      = map { $_->{'package'} => $_->{'state'} } @{$pkgref};
    my $INCLUDE_SYSTEM_PACKAGES_IN_INSTALLED_STATE_LIST = 1;                                                      # this takes about 700ms, but it allows us to pass less to the package system to resolve
    if ($INCLUDE_SYSTEM_PACKAGES_IN_INSTALLED_STATE_LIST) {
        my @installed = $self->list( state => 'installed' );
        ( $pkg_states{$_} ||= 'installed' ) for @installed;
    }
    my %package_map = map { $_->{'package'} => $_ } @$pkgref;
    require Cpanel::PackMan::DepSolver;
    my $dep_solver = Cpanel::PackMan::DepSolver->new(
        'packages_wanted_in_namespaces' => \%pkgs_to_install,
        'package_states'                => \%pkg_states,
        'package_map'                   => \%package_map,
        ( $ns ? ( 'namespaces' => [$ns] ) : () ),
    );
    my $deps = $dep_solver->solve_deps();
    foreach my $pkg (
        keys %{ $deps->{'required'} },
        keys %{ $deps->{'wanted'} }
    ) {
        $_ts_data{'donotremove'}{$pkg} = 1;
    }
    foreach my $pkg ( keys %{ $deps->{'wanted'} } ) {
        next if !exists $pkg_states{$pkg};
        if ( $pkg_states{$pkg} eq 'updatable' ) {
            $_ts_data{'upgrade'}{$pkg} = 1;
        }
        elsif ( $pkg_states{$pkg} eq 'not_installed' ) {
            $_ts_data{'install'}{$pkg} = 1;
        }
    }

    # Erase any haves that are not needed or wanted
    foreach my $pkg ( keys %{ $deps->{'not_wanted'} }, keys %{ $deps->{'wanted'} } ) {
        if ( $deps->{'wanted'}{$pkg} && $deps->{'not_wanted'}{$pkg} ) {
            die "Dep solver wanted “$pkg”and not_wanted “$pkg”\n";    # should never happen
        }
        elsif ( $deps->{'wanted'}{$pkg} ) {
            if ( $deps->{'conflicts'}{$pkg} ) {
                die "The package “$pkg” conflicts and we need to install it resolve deps\n";
            }
        }
        else {    # not wanted
            if ( $deps->{'required'}{$pkg} ) {
                die "The package “$pkg” is required and we need to uninstall it resolve deps\n";
            }
            elsif ( $pkg eq 'glibc' ) {
                die "Something went very wrong because glibc was scheduled for uninstall\n";
            }
        }
    }

    my %pkgs_needed;
    foreach my $pkg ( @do_not_remove, keys %{ $_ts_data{'install'} }, keys %{ $_ts_data{'upgrade'} } ) {
        $pkgs_needed{$pkg} = 1;
    }
    ###############################################################
    #### Step 2: Take list of what we have installed, build remove list based against the
    #### 'donotremove', 'unaffected' (already installed and current version), needed and wanted package lists
    ###############################################################

    my ( $tmp_fh, $tmp_file ) = File::Temp::tempfile( CLEANUP => 1 );

    my %pkgs_wanted;
    @pkgs_wanted{ @{$pkgs_want_ar} } = ();

    # uninstall any haves that are not needed or wanted
    my @carried_over_pkgs;
    foreach my $pkg (@pkgs_have) {
        if ( !$pkgs_needed{$pkg} && !$pkgs_wanted{$pkg} && !$_ts_data{'donotremove'}{$pkg} && !$_ts_data{'unaffected'}{$pkg} ) {
            print {$tmp_fh} "uninstall $pkg\n";
        }
        else {
            push( @carried_over_pkgs, $pkg );
        }
    }

    # Install wanted and needed packages along with those being carried over.
    my $install_seen = {};
    foreach my $pkg ( @{$pkgs_want_ar}, keys %pkgs_needed, @carried_over_pkgs ) {
        next if substr( $pkg, 0, length($ns) + 1 ) ne "$ns-";
        next if $install_seen->{$pkg}++;
        print {$tmp_fh} "install $pkg\n";
    }
    close $tmp_fh;

    $self->die_if_unavailable() if $die_if_unavailable;

    my @shell_output;
    my $line_handler = sub { my $out = shift; push @shell_output, $out; chomp $out; $self->logger->info($out) if $out; return '' };
    my @shell_args   = $self->sys->syscmd_args_txn_dryrun($tmp_file);

    $self->sys->syscmd( $line_handler, @shell_args );

    $self->_parse_syscmd_txn_output( \@shell_output, \%_ts_data );
    Cpanel::Rlimit::restore_rlimits($limits_hr);

    ###################
    #### END LOGIQUE ##
    ###################

    _remove_from_uninstall_if_elsewhere( \%_ts_data );
    _remove_from_unaffected_if_upgrade( \%_ts_data );
    return _build_results_from_ts_data( \%_ts_data );
}

sub _build_results_from_ts_data ($ts_data_ref) {
    my %result;
    for my $type (qw(install upgrade uninstall unaffected)) {
        $result{$type} = [ exists $ts_data_ref->{$type} ? keys %{ $ts_data_ref->{$type} } : () ];
    }

    return \%result;
}

sub resolve_multi_op_ns ( $self, $pkgs_want_ar = [], $ns = undef, $die_if_unavailable = 0 ) {    ## no critic qw(Subroutines::ProhibitExcessComplexity Subroutines::ProhibitManyArgs)

    # We need to free ourselves from the memory restrictions here to avoid the following error (seen after some time) running deplist
    #   Fatal Python error: Couldn't create autoTLSkey mapping
    my $limits_hr = Cpanel::Rlimit::get_current_rlimits();
    Cpanel::Rlimit::set_rlimit_to_infinity();

    die "Namespace is required.\n" if !$ns;

    if ( $ns !~ m/^[a-z][a-z0-9]+$/ ) {
        die "Namespace must start with a letter, be at least two characters long, and only contain ascii a-z0-9\n";
    }

    ###############################################################
    #### Step 1: Examine the current package state in order to
    #### generate %_ts_data
    ###############################################################
    my %_ts_data                          = ();
    my %packages_wanted_in_this_namespace = map { $_ => 1 } @{$pkgs_want_ar};
    my $prefix                            = $ns . '-';
    my $prefix_length                     = length $prefix;
    my $pkgref                            = $self->multi_pkg_info( 'prefixes' => [$prefix], 'disable-excludes' => 1 );
    my %pkg_states                        = map { $_->{'package'} => $_->{'state'} } @{$pkgref};

    my $INCLUDE_SYSTEM_PACKAGES_IN_INSTALLED_STATE_LIST = 1;    # this takes about 700ms, but it allows us to pass less to the package system to resolve
    if ($INCLUDE_SYSTEM_PACKAGES_IN_INSTALLED_STATE_LIST) {
        my @installed = $self->list( state => 'installed' );
        ( $pkg_states{$_} ||= 'installed' ) for @installed;
    }
    my %package_map = map { $_->{'package'} => $_ } @$pkgref;

    if ( $ns eq 'ea' ) {
        $packages_wanted_in_this_namespace{'ea-profiles-cpanel'} = 1;
    }
    elsif ( !-f "/etc/cpanel/ea4/additional-pkg-prefixes/$ns" ) {
        die "Unknown namespace “$ns” given.\n";
    }

    require Cpanel::PackMan::DepSolver;
    my $dep_solver = Cpanel::PackMan::DepSolver->new(
        'packages_wanted_in_namespaces' => \%packages_wanted_in_this_namespace,
        'package_states'                => \%pkg_states,
        'package_map'                   => \%package_map,
        'namespaces'                    => [$ns],
    );
    my $deps = $dep_solver->solve_deps();
    ###############################################################
    #### Step 2: Take list of what we have installed, build remove list based against the
    #### 'donotremove', 'unaffected' (already installed and current version), needed and wanted package lists
    ###############################################################

    my ( $tmp_fh, $tmp_file ) = File::Temp::tempfile( CLEANUP => 1 );

    # Erase any haves that are not needed or wanted
    foreach my $pkg ( keys %{ $deps->{'not_wanted'} }, keys %{ $deps->{'wanted'} } ) {
        $pkg_states{$pkg} ||= 'not_installed';

        if ( $deps->{'wanted'}{$pkg} && $deps->{'not_wanted'}{$pkg} ) {
            die "Dep solver wanted “$pkg” and not_wanted “$pkg”\n";    # should never happen
        }
        elsif ( $deps->{'wanted'}{$pkg} ) {
            if ( $deps->{'conflicts'}{$pkg} ) {
                die "The package “$pkg” conflicts and we need to install it resolve deps\n";
            }
            elsif ( $pkg_states{$pkg} eq 'not_installed' ) {
                next if substr( $pkg, 0, length($ns) + 1 ) ne "$ns-";
                print {$tmp_fh} "install $pkg\n";
            }
            elsif ( $pkg_states{$pkg} eq 'updatable' ) {
                print {$tmp_fh} "update $pkg\n";
            }
            elsif ( $pkg_states{$pkg} ne 'installed' ) {
                die "The state for “$pkg” is invalid: “$pkg_states{$pkg}”\n";
            }
        }
        else {    # not wanted
            if ( $deps->{'required'}{$pkg} ) {
                die "The package “$pkg” is required and we need to uninstall it resolve deps\n";
            }
            elsif ( $pkg_states{$pkg} eq 'installed' || $pkg_states{$pkg} eq 'updatable' ) {
                if ( $pkg eq 'glibc' ) {
                    die "Something went very wrong because glibc was scheduled for uninstall\n";
                }
                print {$tmp_fh} "uninstall $pkg\n";
            }
            elsif ( $pkg_states{$pkg} ne 'not_installed' ) {
                die "The state for “$pkg” is invalid: “$pkg_states{$pkg}”\n";
            }
        }
    }

    close $tmp_fh;

    $self->die_if_unavailable() if $die_if_unavailable;

    my @shell_output;
    my $line_handler = sub { my $out = shift; push @shell_output, $out; chomp $out; $self->logger->info($out) if $out; return ''; };
    my @shell_args   = $self->sys->syscmd_args_txn_dryrun($tmp_file);

    $self->sys->syscmd( $line_handler, @shell_args );

    $self->_parse_syscmd_txn_output( \@shell_output, \%_ts_data );
    if ( $_ts_data{'uninstall'}{'glibc'} ) {
        die "Something went very wrong because glibc was scheduled for uninstall\n";
    }

    foreach my $pkg ( keys %{ $deps->{'not_wanted'} }, keys %{ $deps->{'wanted'} } ) {
        if ( substr( $pkg, 0, $prefix_length ) eq $prefix && $pkg_states{$pkg} ne 'not_installed' && !$_ts_data{'install'}{$pkg} && !$_ts_data{'upgrade'}{$pkg} && !$_ts_data{'uninstall'}{$pkg} ) {
            $_ts_data{'unaffected'}{$pkg} = 1;
        }
    }

    Cpanel::Rlimit::restore_rlimits($limits_hr);

###################
#### END LOGIQUE ##
###################

    _remove_from_uninstall_if_elsewhere( \%_ts_data );
    _remove_from_unaffected_if_upgrade( \%_ts_data );
    return _build_results_from_ts_data( \%_ts_data );
}

sub _remove_from_unaffected_if_upgrade ($ts_data_ref) {

    if ( exists $ts_data_ref->{unaffected} && exists $ts_data_ref->{upgrade} ) {
        for my $upg ( keys %{ $ts_data_ref->{upgrade} } ) {
            delete $ts_data_ref->{unaffected}{$upg} if exists $ts_data_ref->{unaffected}{$upg};
        }
    }

    return;
}

sub _remove_from_uninstall_if_elsewhere ($ts_data_ref) {

    # this can happen if $un is a dep of something being kept and something being uninstalled, go figure …
    if ( exists $ts_data_ref->{uninstall} ) {
        for my $type (qw(install upgrade unaffected)) {
            next if !exists $ts_data_ref->{$type};
            for my $un ( keys %{ $ts_data_ref->{uninstall} } ) {
                delete $ts_data_ref->{uninstall}{$un} if $ts_data_ref->{$type}{$un};
            }
        }
    }

    return 1;
}

sub _parse_for_errors ( $self, $lines_ar ) {
    my @errors = $self->sys->parse_lines_for_errors($lines_ar);
    _log_lines_then_die( $lines_ar, @errors ) if @errors;
    return;
}

sub _parse_syscmd_txn_output ( $self, $lines_ar, $trans_data ) {
    my @errors = $self->sys->parse_syscmd_txn_output( $lines_ar, $trans_data );
    _log_lines_then_die( $lines_ar, @errors ) if @errors;
    return;
}

my $_log_lines_then_die = {};    # prevent same second calls from writing to the same file

sub _log_lines_then_die ( $lines_ar, @errors ) {
    my $error = join( "\n", @errors );

    if ( !-d _error_log_dir() ) {
        Cpanel::SafeDir::MK::safemkdir( _error_log_dir() ) or die sprintf( "Could not mkdir “%s”: $!\n", _error_log_dir() );
    }

    $_log_lines_then_die->{$$}++;
    my $log = _error_log_dir() . '/' . ( split( /\s+/, Cpanel::Time::Local::localtime2timestamp( undef, "_" ) ) )[0] . "-$_log_lines_then_die->{$$}";
    Cpanel::FileUtils::Write::write( $log, join( "\n", @{$lines_ar} ) );

    $error .= "\nThe entire output was logged to: $log\n";
    die $error;
}

sub list ( $self, %query ) {
    my $type;
    if ( !exists $query{state} || !defined $query{state} || $query{state} eq 'any' ) {
        $type = 'all';
    }
    elsif ( $query{state} eq 'not_installed' ) {
        $type = 'available';
    }
    elsif ( $query{state} eq 'updatable' ) {
        $type = 'updates';
    }
    elsif ( $query{state} eq 'installed' ) {
        $type = 'installed';
    }
    else {
        die "Unknown state given ($query{state}).\n";
    }

    my $raw_ar = $self->sys->list( $type, ( $query{prefix} ? $query{prefix} : () ) );
    return if !$raw_ar;

    return sort @{$raw_ar};    ## no critic qw(Subroutines::ProhibitReturnSort)
}

sub multi_pkg_info ( $self, %args ) {
    my $raw_aoh = $self->sys->multi_info(%args);
    return if !$raw_aoh;

    my @pkg_hrs;
    for my $pkg_hr ( @{$raw_aoh} ) {
        next if !$pkg_hr;
        push @pkg_hrs, $self->sys->normalize_pkg_hr($pkg_hr);
    }
    return \@pkg_hrs;
}

sub pkg_hr ( $self, $name ) {
    my $raw_hr = $self->sys->info($name);
    return if !$raw_hr;

    return $self->sys->normalize_pkg_hr($raw_hr);
}

sub die_if_unavailable ($self) {
    die "Package system is currently busy — cannot proceed at this time\n" if $self->sys->is_unavailable();
    return;
}

sub _error_log_dir {
    return "$_LOGS_BASE/packman/errors";
}

1;

__END__

=encoding utf-8

=head1 NAME

Cpanel::PackMan - Object oriented OS agnostic cPanel package management

=head1 VERSION

This document describes Cpanel::PackMan version 0.02

=head1 SYNOPSIS

    my $ea4 = Cpanel::PackMan->instance(type => 'ea4');

    for my $pkg ( $ea4->list(state => 'installed') ) {
        say $pkg->{package} if !$ea4->is_uptodate($pkg->{package})
    }

=head1 DESCRIPTION

Object to interact with cPanel package management.

It is OS agnostic by leveraging C<Cpanel::OS>.

=head1 INTERFACE

=head2 Constructors

=head3 new()

This will create and return a new object everytime.

Its options are described under </ATTRIBUTES>.

=head3 instance()/multiton()

Like new() but returns the same object on subsequent calls using the same arguments.

=head2 ATTRIBUTES

=head3 type

Value can be 'packman' or 'ea4'. Default is 'packman'

Can not be set after object instantiation.

=head3 build

Lazy Façade for the L<Cpanel::PackMan::Build> object.

Can not be given during object instantiation.

=head3 sys

Lazy Façade for the L<Cpanel::PackMan::Sys> object.

=head2 Methods

=head3 list

Returns a list of packages.

With no arguments it returns all packages available installed or not.

The results can be filtered and limited with the following options:

=over 4

=item state

If not given, not defined, or with a value of 'any' it will return all packages.

If the value is 'not_installed' it will return only packages that are not installed.

If the value is 'updatable' it will return only installed packages that have updates available.

If the value is 'installed' it will return only installed packages.

Any other value will die with an unknown state error in order to catch our mistake at development time.

=item prefix

Optional, if given it will only return results that start with given string..

=back

=head3 pkg_hr

Returns a hashref of a package’s information (or nothing if the package does not exist).

The only argument is the package you want information for.

The hashref will contain these keys:

=over 4

=item package

e.g. perl

=item architecture

e.g. i386

=item size

e.g. 29736313

=item release

e.g. 43.el5_11

=item version

e.g. 5.8.8

=item short_description

e.g. The Perl programming language

=item long_description

e.g. Perl is a high-level programming language with roots in C, sed, awk and shell scripting.  Perl is good at handling pro
cesses and files, and is especially good at handling text.  Perl's hallmarks are practicality and efficiency.  While it is used to do a lot of differe
nt things, Perl's most common applications are system administration utilities and web programming.  A large proportion of the CGI scripts on the web
are written in Perl.  You need the perl package installed on your system so that your system can handle Perl scripts.  Install this package if you want
 to program in Perl or enable your system to handle Perl scripts.

=item more_info_url

e.g. http://www.perl.org/

=item license

e.g. Artistic or GPL

=item pkg_dep

A hashref with the following keys:

Note: on RPM based systems these are not populated in C<pkg_hr()> for optimization reason but they are in C<multi_pkg_info()>.

=over 4

=item requires

An arrayref containing a list of packages that this package requires.

Each item is either a package name or an array ref. The array ref is intended to be an or-list.

e.g. C<'foo', [ 'bar', 'baz' ]> means “foo and either bar or baz”.

=item conflicts

An arrayref containing a list of packages that this package conflicts with.

=back

=item repo_name

Name of repository for the package

=item vendor

Name of the entity providing/maintaining this package. e.g. cPanel

=item pkg_group

Name of the package group

=item version_latest

The C<version>-C<release> of what is available.

=item version_installed

The C<version>-C<release> of what is installed.

=item state

The state of the package in relation to the system.

Can be 'installed', 'updatable', or 'not_installed'.

=back

If the environment variable PACKMAN_DEBUG is true it will also incldue 'pkg_dep_raw' which is like 'pkg_dep' but it is the raw data from the backend library.

=head3 multi_pkg_info

Returns an array ref of pkg_hr() type hashrefs.

It takes a hash with the following optional keys:

=over 4

=item 'packages'

An array ref of packages you want information for.

If a package does not exist it is left out of the results.

=item 'prefixes'

An array ref of prefixes to incldue in the results.

=item 'disable-excludes'

A boolean of whether or not to disable excludes. Default if false.

=back

=head3 is_installed

Takes a package or a pkg_hr. Returns true (the pkg_hr for convienience) if it is installed and false otherwise.

=head3 is_uptodate

Takes a package or a pkg_hr. Returns true (the pkg_hr for convienience) if it is up to date and false otherwise.

=head3 multi_op

Do multiple operations in one call.

Returns false if no valid operation data was given. Returns the count of operations that were run.

Takes a hashref whose keys are the operation and the value is an array ref of things to operate on.

Valid operations are:

=over 4

=item install

Value is a list of packages to install.

=item upgrade

Value is a list of packages to upgrade.

=item uninstall

Value is a list of packages to uninstall.

=back

An optional second argument is a boolean that makes the system output quiet when true. Default is false.

=head3 resolve_multi_op

Takes an array ref of packages that you want to ensure are installed and up to date and are the only ones in the set (e.g. ea-*) installed.

Then it asks the package system to resolve that with the current state of the system into information about what needs done to get to that state.

Returns a hashref suitable for multi_op() with one self-explanatory extra field: unaffected.

A second, optional, argument can supply a name space that represents a set of packages. It is used to determine packages that are installed that we want removed given our package list and also any packages that are always required but can not be guaranteed by package dependencies alone.

For example, in ea4 profiles we supply a list of ea- prefixed packages we want. Implying that we do not want any other ea- prefixed packages (sans dependencies of course). This will ensure those get factored into the resolution and uninstalled if possible.

'ea' is currently the only valid value.

A third, optional, argument will, if true, cause the function to die if the package system is unavailable to do the operation.

=head3 resolve_multi_op_ns

The same as resolve_multi_op except:

=over 4

=item the second argument is required

=item it has been optimized more

=back

The results should be the same as a call to resolve_multi_op w/ the optional second arg, it will just faster.

=head3 die_if_unavailable

Takes no arguments. Dies if the package system is not available to do an operation.
