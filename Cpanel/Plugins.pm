package Cpanel::Plugins;

# cpanel - Cpanel/Plugins.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::Plugins - installing/uninstalling cPanel plugins via yum

=head1 SYNOPSIS

    #Will add the package repository as necessary.
    Cpanel::Plugins::install_plugins('plugin1', 'plugin2');

    #Will remove the package repository if it’s unused after removing
    #the plugin’s RPM.
    Cpanel::Plugins::uninstall_plugins('plugin3');

=cut

use cPstrict;

use Cpanel::Exception     ();
use Cpanel::Pkgr          ();
use Cpanel::Plugins::Repo ();
use Cpanel::SysPkgs       ();

# Some plugins need a little work before the packager can install them.
# Each code ref must return either an empty list or a list of additional packages to install as
# part of the same transaction. This is not the same as an RPM dependency, because the additional
# packages can still be uninstalled later if desired.
my %plugin_bootstrap = (
    'cpanel-ccs-calendarserver' => sub { return 'cpanel-z-push' },
);

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 uninstall_and_install_plugins( \@OLD, \@NEW )

A combination of C<uninstall_plugins()> and C<install_plugins()>,
but with the changes done under a single yum transaction.

Use this, e.g., to replace one plugin with another without
worrying about what happens if the new one’s installation fails.

=cut

sub uninstall_and_install_plugins ( $old_ar, $new_ar ) {
    _get_pkg_obj()->uninstall_packages( 'packages' => $old_ar );
    return _get_pkg_obj()->install_packages( 'packages' => $new_ar );
}

=head2 install_plugins( @PLUGIN_NAMES )

Installs the plugins that @PLUGIN_NAMES (e.g., C<cpanel-letsencrypt-v2>)
specifies.

Note that no named plugins should be installed at the time when this
function is called. If you need install-or-update logic, see
C<install_or_upgrade_plugins()>.

=cut

sub install_plugins (@plugins) {

    _check_input_plugin_names(@plugins);

    Cpanel::Plugins::Repo::install();

    my @additional_packages;
    for my $plug (@plugins) {
        my $coderef = $plugin_bootstrap{$plug};
        if ( defined($coderef) ) {
            push @additional_packages, $coderef->();
        }
    }

    return _get_pkg_obj()->install_packages(
        packages => [ @plugins, @additional_packages ],
    );
}

=head2 reinstall_plugins( @PLUGIN_NAMES )

Does the same thing as C<install_plugins> but instead reinstalls the packages.
The primary purpose of this is to ensure that dependencies of a package are
still installed even when the target package is.

=cut

sub reinstall_plugins (@plugins) {

    _check_input_plugin_names(@plugins);

    Cpanel::Plugins::Repo::install();

    for my $plug (@plugins) {
        my $coderef = $plugin_bootstrap{$plug};
        if ( defined($coderef) ) {
            $coderef->();
        }
    }

    return _get_pkg_obj()->reinstall_packages(
        packages => \@plugins,
    );
}

=head2 uninstall_plugins( @PLUGIN_NAMES )

The reverse of C<install_plugins()>.

=cut

sub uninstall_plugins (@plugins) {

    _check_input_plugin_names(@plugins);

    my %opts = ( packages => \@plugins );
    if ( grep { 'cpanel-ccs-calendarserver' eq $_ } @plugins ) {
        $opts{'exclude_packages'} = [qw{postgresql postgresql-server}];
    }

    _get_pkg_obj()->uninstall_packages(%opts);

    return;
}

=head2 install_or_upgrade_plugins( @PLUGIN_NAMES )

Like C<install_plugins()> but will upgrade any already-installed plugins.

=cut

sub install_or_upgrade_plugins (@plugins) {

    _check_input_plugin_names(@plugins);

    require File::Temp;
    require Cpanel::Autodie;
    require Cpanel::FileUtils::Dir;

    my $yum = _get_pkg_obj();

    my $dir = File::Temp::tempdir( CLEANUP => 1 );

    Cpanel::Plugins::Repo::install();

    # File::Temp::tempdir perms are 0700 but to allow some package managers
    # (apt) to perform a download as a non-root user the tempdir needs to at
    # least be traversable by 'other'.
    Cpanel::Autodie::chmod( 0711, $dir );

    $yum->download_packages(
        packages     => \@plugins,
        download_dir => $dir,
    );

    my $pkgs_ar = Cpanel::FileUtils::Dir::get_directory_nodes($dir);

    require Cpanel::PackMan;
    my $pkg_ext = Cpanel::PackMan->instance->sys->ext;
    $pkgs_ar = [ grep { $_ =~ m/\.${pkg_ext}$/ } @$pkgs_ar ];
    return unless @$pkgs_ar;
    substr( $_, 0, 0, "$dir/" ) for @$pkgs_ar;

    # Note, the below "fails deadly", so be aware as a caller
    return Cpanel::Pkgr::install_or_upgrade_from_file(@$pkgs_ar);
}

=head2 is_plugin_installed( $PLUGIN_NAME )

Returns 1 if $PLUGIN_NAME is installed, or 0 otherwise .

=cut

sub is_plugin_installed ($plugin) {
    return Cpanel::Pkgr::is_installed($plugin);
}

=head2 is_pkg_unaltered( $PLUGIN_NAME )

Returns 1 if $PLUGIN_NAME is unaltered, or 0 otherwise.

=cut

sub is_pkg_unaltered ($plugin) {
    return Cpanel::Pkgr::verify_package($plugin);
}

#----------------------------------------------------------------------

sub _get_pkg_obj {
    return Cpanel::SysPkgs->new();
}

sub _check_input_plugin_names (@plugins) {

    if ( !@plugins ) {
        die Cpanel::Exception::create_raw( 'Empty', 'Submit at least one plugin.' );
    }

    return;
}

1;
