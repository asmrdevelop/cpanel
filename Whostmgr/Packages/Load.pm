package Whostmgr::Packages::Load;

# cpanel - Whostmgr/Packages/Load.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Whostmgr::ACLS                       ();
use Whostmgr::Packages::Info::Modular    ();
use Cpanel::Config::Constants            ();
use Cpanel::Debug                        ();
use Cpanel::ConfigFiles                  ();
use Cpanel::Config::LoadConfig           ();
use Cpanel::Validate::FilesystemNodeName ();

use constant _ENOENT => 2;

=encoding utf-8

=head1 NAME

Whostmgr::Packages::Load - Tools for loading packages.

=head1 SYNOPSIS

    use Whostmgr::Packages::Load;

    my $package_data = Whostmgr::Packages::Load::load_package($name, $status_ref);

    if ($package_data->{'IP'}) {
        # has ip.
    }

=cut

=head2 package_dir

Returns the path to the packages directory containing the package files.

=cut

sub package_dir {
    return "$Cpanel::ConfigFiles::PACKAGES_DIR/";
}

=head2 package_extensions_dir

Returns the path to the packages extensions directory containing the package extension files.

=cut

sub package_extensions_dir {
    return package_dir() . "extensions/";
}

=head2 load_package_file_raw($file)

Loads a package file and returns a hashref.  If the package file
does not exist or cannot be opened, an empty hashref is returned.

Example hashref:
        {
            'QUOTA'                     => 'unlimited',
            'DIGESTAUTH'                => 'n',
            'CGI'                       => 'y',
            'MAX_DEFER_FAIL_PERCENTAGE' => 'unlimited',
            'LANG'                      => 'en',
            ...,
        }

=cut

sub load_package_file_raw {
    my $file = shift or return {};

    return ( Cpanel::Config::LoadConfig::loadConfig( $file, undef, '=' ) || {} );
}

=head2 load_package($pkg, $result_hashref, $need_to_check)

Loads a package file and returns a hashref if the package file is opened.
If the package file does not exist or cannot be opened, nothing is returned.

Example hashref:
        {
            'QUOTA'                     => 'unlimited',
            'DIGESTAUTH'                => 'n',
            'CGI'                       => 'y',
            'MAX_DEFER_FAIL_PERCENTAGE' => 'unlimited',
            'LANG'                      => 'en',
            ...,
        }

If $result_hashref is passed, the C<result> and C<reason> keys will be set
in the hashref based on the result of the loading.

Example hashref after calling this function:
        {
          'result' => 1,
          'reason' => 'OK'
        }

If $need_to_check is true, WHM ACLS are checked to make sure that the user
set in $ENV{'REMOTE_USER'} is permitted to load the package.  If the user
is not permitted to load the package load_package will return undef
and an error in $result_hashref (if given).

=cut

sub load_package ( $pkg, $result_hashref = undef, $need_to_check = 0, @ ) {    ## no critic qw(ManyArgs)
    return _load_package( $pkg, $result_hashref || {}, $need_to_check );
}

sub _load_package ( $pkg, $result_hashref, $need_to_check, $if_exists_yn = 0 ) {    ## no critic qw(ManyArgs)
    my $is_valid_pkg = 0;
    $is_valid_pkg = 1 if !$need_to_check || user_may_view_package( $ENV{'REMOTE_USER'}, $pkg );

    # Prevent directory traversal attempts.
    $is_valid_pkg = 0 if !Cpanel::Validate::FilesystemNodeName::is_valid($pkg);

    if ( !$is_valid_pkg ) {
        my $msg = "Invalid package $pkg";
        Cpanel::Debug::log_info($msg);
        $result_hashref->{'result'} = 0;
        $result_hashref->{'reason'} = $msg;
        return;
    }

    $result_hashref->{'result'} = 1;
    $result_hashref->{'reason'} = 'OK';

    my $pk_ref = Cpanel::Config::LoadConfig::loadConfig( package_dir() . $pkg, undef, '=' );
    if ( !$pk_ref && $pkg ne 'default' ) {
        if ( $if_exists_yn && $! == _ENOENT() ) {
            return;
        }

        my $msg = "Failed to load package “$pkg”: $!";
        Cpanel::Debug::log_info($msg);
        $result_hashref->{'result'} = 0;
        $result_hashref->{'reason'} = $msg;
    }

    delete $pk_ref->{''};

    # We used to attempt delete invalid keys but
    # we were operating in scalar context so it
    # did nothing
    if ( grep { length > 50 } keys %$pk_ref ) {
        my $msg = "Package contents contain invalid key: “$pkg”: $!";
        Cpanel::Debug::log_info($msg);
        $result_hashref->{'result'} = 0;
        $result_hashref->{'reason'} = $msg;
        return;
    }

    for my $component ( Whostmgr::Packages::Info::Modular::get_enabled_components() ) {
        $pk_ref->{ $component->name_in_package() } //= $component->default();
    }

    # TODO: Deduplicate these values with Whostmgr::Packages::Info:
    $pk_ref->{'IP'}          ||= 'n';
    $pk_ref->{'FEATURELIST'} ||= 'default';
    $pk_ref->{'LANG'}        ||= 'en';
    $pk_ref->{'DIGESTAUTH'}  ||= 'n';
    $pk_ref->{'CPMOD'}       ||= do {         ## If we don't have a CPMOD value, get the default from wwwconfig, and if all else fails go with the system default.
        require Cpanel::Config::LoadWwwAcctConf;
        require Cpanel::Config::Constants;
        my $wwwacctconf = Cpanel::Config::LoadWwwAcctConf::loadwwwacctconf();
        $wwwacctconf->{DEFMOD} || do {
            warn "$Cpanel::Config::LoadWwwAcctConf::wwwacctconf: no default theme; using default ($Cpanel::Config::Constants::DEFAULT_CPANEL_THEME)\n";
            $Cpanel::Config::Constants::DEFAULT_CPANEL_THEME;
        };
    };

    # Case CPANEL-20909: Work around for cases where we previously allowed settings greater than 100%
    my $max_deferral_setting = $pk_ref->{'MAX_DEFER_FAIL_PERCENTAGE'};
    if ( defined $max_deferral_setting && $max_deferral_setting !~ tr{0-9}{}c && $max_deferral_setting > 100 ) {
        $pk_ref->{'MAX_DEFER_FAIL_PERCENTAGE'} = 100;
    }
    return $pk_ref;
}

=head2 user_may_view_package($username, $package_name)

Returns a boolean result based on whether the given user is permitted to view
the details of a given package. This access is granted if any of the following
are true:

=over

=item

The user is the root user.

=item

The package name is prefixed with the user's name (e.g. user123 owns user123_pkg123).
This convention is used to establish ownership of the package.

=item

It is a global package (no underscores in the package name) and the user has the
"viewglobalpackages" ACL.

=item

The user is "allowed" to create users using the package, based on the package's
defined limits.

=back

=cut

sub user_may_view_package ( $username, $package_name ) {
    if (
           Whostmgr::ACLS::hasroot()
        || $package_name =~ m{\A\Q$username\E_}
        || ( $package_name !~ tr/_//
            && Whostmgr::ACLS::checkacl('viewglobalpackages') )
    ) {
        return 1;
    }

    # Check using the lesser-used "limits" method of providing access.
    require Whostmgr::Limits::PackageLimits;
    my $package_limits = Whostmgr::Limits::PackageLimits->load_by_reseller($username);
    return $package_limits && $package_limits->create_for_reseller( $package_name, $username ) || 0;
}

=head2 $pkg_or_undef = load_package_if_exists( $NAME, \%RESULT, $NEED_TO_CHECK )

Like C<load_package()> but considers nonexistence of the package not to be
a failure case. Still returns empty in that case. Also, for this function
\%RESULT is mandatory.

=cut

sub load_package_if_exists ( $pkg, $result_hashref, $need_to_check = 0 ) {    ## no critic qw(ManyArgs)
    return _load_package( $pkg, $result_hashref, $need_to_check, 1 );
}

sub get_all_package_extensions {
    my $package_extensions_dir = package_extensions_dir();
    $package_extensions_dir =~ s{/$}{};                                       # Remove the trailing slash.

    # If root, try to mkdir on package_dir()
    if ( !-d $package_extensions_dir && $> == 0 ) {
        unlink $package_extensions_dir;                                       # Just in case it's a file.
        mkdir $package_extensions_dir, 0700;
    }

    # Get a list of files which have a matching .tt2 file to go with them.
    my @extension_files;
    if ( opendir my $pkgdir_fh, $package_extensions_dir ) {
        $package_extensions_dir .= '/';
        @extension_files = map { s/\.tt2$//; ( -e $package_extensions_dir . $_ ) ? $_ : () } grep { /\.tt2/ } grep { !-d $package_extensions_dir . $_ } readdir $pkgdir_fh;    ## no critic qw(ControlStructures::ProhibitMutatingListFunctions)
        closedir $pkgdir_fh;
    }

    my %extensions_hash;
    my %defaults;
    foreach my $extension ( sort @extension_files ) {
        my $extension_defaults = load_package_file_raw("$package_extensions_dir/$extension");
        $extensions_hash{$extension} = $extension_defaults->{'_NAME'} || 'unknown';
        foreach my $key ( keys %$extension_defaults ) {
            next if ( $key eq '_NAME' );    # _NAME is not an allowed default.
            $defaults{$key} = $extension_defaults->{$key};
        }
    }

    return \%extensions_hash, \%defaults;
}

1;
