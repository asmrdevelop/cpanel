package Cpanel::SysPkgs;

# cpanel - Cpanel/SysPkgs.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

Cpanel::SysPkgs

=head1 DESCRIPTION

Cpanel::SysPkgs provides an abstraction layer to query the upstream packaging system about what is available and possibly install/uninstall those things.

This interface IS NOT for querying the local system about what is installed. For that, we recommend you use Cpanel::Pkgr.

=head1 SYNOPSIS

    my $syspkgs = Cpanel::SysPkgs->new;
    $syspkgs->download_packages( @pkgs );
    $syspkgs->install( 'packages' => ['epel-release'] );
    ...

=cut

use cPstrict;

use Cpanel::OS ();

# This is used in updatenow. As such use all modules, all the time
use Cpanel::SysPkgs::APT ();    # PPI USE OK - See above line
use Cpanel::SysPkgs::DNF ();    # PPI USE OK - See above line
use Cpanel::SysPkgs::YUM ();    # PPI USE OK - See above line

$Cpanel::SysPkgs::VERSION = '1.1';

our $OUTPUT_OBJ_SINGLETON;      # For EasyApache

our %DEFAULT_EXCLUDE_OPTIONS = (
    'kernel'      => 0,
    'bind-chroot' => 1,
);

#----------------------------------------------------------------------
#NOTE: This returns an object that is NOT a Cpanel::SysPkgs instance!
#----------------------------------------------------------------------
#
sub new ( $class, %args ) {
    my $self = bless {%args}, $class;

    # This can probably go away, but there's a lot of places this is called from
    $self->{'exclude_options'} ||= {%DEFAULT_EXCLUDE_OPTIONS};
    $self->{'output_obj'}      ||= $OUTPUT_OBJ_SINGLETON;

    # Consider adding a "package handling module" symlink in os.d/ ?
    my $pkg_mgr = uc( Cpanel::OS::package_manager() );
    my $pkg_nam = "Cpanel::SysPkgs::$pkg_mgr";

    my $new = $pkg_nam->can("new") or die("Couldn't load $pkg_nam!");
    $self = $new->( $pkg_nam, $self ) or die("Could not convert SysPkgs Object to $pkg_nam");

    return $self;
}

1;
