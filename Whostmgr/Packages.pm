package Whostmgr::Packages;

# cpanel - Whostmgr/Packages.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;
no warnings;    ## no critic qw(ProhibitNoWarnings) -- not yet warnings safe

use Cpanel::AcctUtils::Load ();
use Cpanel::ConfigFiles::Apache 'apache_paths_facade';    # see POD for import specifics
use Cpanel::Config::CpUserGuard ();
use Cpanel::SafeFile            ();
use Cpanel::FileUtils::Move     ();
use Cpanel::LoadFile            ();
use Whostmgr::ACLS              ();
use Whostmgr::AcctInfo          ();
use Whostmgr::AcctInfo::Plans   ();
use Whostmgr::Packages::Authz   ();
use Whostmgr::Packages::Load    ();
use Whostmgr::Packages::Info    ();
use Whostmgr::Packages::Fetch   ();
use Whostmgr::Packages::Exists  ();
use Cpanel::LoadModule          ();

use Cpanel::Imports;

{
    no warnings 'once';
    *package_extensions_dir     = *Whostmgr::Packages::Load::package_extensions_dir;
    *package_dir                = *Whostmgr::Packages::Load::package_dir;
    *load_package               = *Whostmgr::Packages::Load::load_package;
    *load_package_file_raw      = *Whostmgr::Packages::Load::load_package_file_raw;
    *get_all_package_extensions = *Whostmgr::Packages::Load::get_all_package_extensions;
    *get_package_items          = *Whostmgr::Packages::Info::get_package_items;
    *get_defaults               = *Whostmgr::Packages::Info::get_defaults;
    *validate_package_options   = *Whostmgr::Packages::Info::validate_package_options;
    *package_exists             = *Whostmgr::Packages::Exists::package_exists;
}

sub _listpkgs {
    my %OPTS = @_;

    my @RSD;

    Cpanel::AcctUtils::Load::loadaccountcache();

    my $want = $OPTS{'want'} || 'creatable';

    my $pkglist_ref = Whostmgr::Packages::Fetch::fetch_package_list( 'want' => $want );
    foreach my $pkg ( sort keys %{$pkglist_ref} ) {
        push( @RSD, { 'name' => $pkg, %{ $pkglist_ref->{$pkg} } } );
    }
    return @RSD;
}

sub _current_reseller_can_use_package ($packagename) {

    require Whostmgr::Packages::Exists;
    my $exists = Whostmgr::Packages::Exists::package_exists($packagename);

    return $exists && Whostmgr::Packages::Authz::current_reseller_can_use_package($packagename);
}

sub _killpkg {
    my %OPTS    = @_;
    my $package = $OPTS{'pkg'};

    if ( !_current_reseller_can_use_package($package) ) {
        return ( 0, _package_does_not_exist_error($package) );
    }

    local $@;
    require Cpanel::LinkedNode::Worker::WHM::Packages;
    my @return = eval { Cpanel::LinkedNode::Worker::WHM::Packages::kill_package_if_exists($package) };

    if ($@) {
        return wantarray ? ( 0, $@ ) : 0;
    }

    return wantarray ? @return : $return[0];
}

sub _package_does_not_exist_error {
    my ($package) = @_;
    if ( Whostmgr::ACLS::hasroot() ) {
        return locale->maketext( 'The package “[_1]” does not exist.', $package );
    }

    # package_exists excludes packages that a reseller would not have access to
    # or also do not exist so this error need to handle both states
    return locale->maketext( 'You do not have access to a package named “[_1]”.', $package );
}

sub __killpkg {

    my %OPTS    = @_;
    my $package = $OPTS{'pkg'};

    if ( !$package || $package eq '' ) {
        my $error = locale->maketext('You must specify a package.');
        return wantarray ? ( 0, locale->maketext( 'There was an error when the system attempted to delete the package “[_1]”: [_2]', $package || "", $error ) ) : 0;
    }

    require Cpanel::Validate::FilesystemNodeName;
    if ( !Cpanel::Validate::FilesystemNodeName::is_valid($package) ) {
        my $error = locale->maketext( "Sorry, “[_1]” is not a valid package name.", $package );
        return wantarray ? ( 0, locale->maketext( 'There was an error when the system attempted to delete the package “[_1]”: [_2]', $package, $error ) ) : 0;
    }

    if ( !_current_reseller_can_use_package($package) ) {
        my $error = _package_does_not_exist_error($package);
        return wantarray ? ( 0, locale->maketext( 'There was an error when the system attempted to delete the package “[_1]”: [_2]', $package, $error ) ) : 0;
    }

    my %ACCTS = Whostmgr::AcctInfo::acctamts( $ENV{'REMOTE_USER'} );
    if ( defined $ACCTS{$package} && $ACCTS{$package} > 0 ) {
        return wantarray ? ( 0, locale->maketext( 'You must move all accounts using the package “[_1]” to another package before removing it.', $package ) ) : 0;
    }
    else {
        my $package_dir = package_dir();
        if ( !unlink( $package_dir . $package ) ) {
            return wantarray ? ( 0, locale->maketext( 'There was an error when the system attempted to delete the package “[_1]”: [_2]', $package, $! ) ) : 0;
        }
    }

    return wantarray ? ( 1, locale->maketext('The system successfully deleted the package.') ) : 1;
}

#Note:
#IP in the cpuser file is an actual IP address; thus, it would only
#make sense to convert from package to cpuser if package IP==n.
sub convert_package_to_cpuser_keys {
    my $pkg_hr = shift;

    if ( exists $pkg_hr->{'BWLIMIT'} && $pkg_hr->{'BWLIMIT'} !~ m{\D} ) {
        $pkg_hr->{'BWLIMIT'} *= 1024 * 1024;
    }
    if ( exists $pkg_hr->{'QUOTA'} && $pkg_hr->{'QUOTA'} !~ m{\D} ) {
        $pkg_hr->{'QUOTA'} *= 1024 * 1024;
    }
    if ( exists $pkg_hr->{'HASSHELL'} ) {
        $pkg_hr->{'HASSHELL'} =~ tr{yn}{10};
    }

    #These use ||= to avoid clobbering an existing value.
    if ( exists $pkg_hr->{'CGI'} ) {
        $pkg_hr->{'HASCGI'} ||= delete $pkg_hr->{'CGI'};
        $pkg_hr->{'HASCGI'} =~ tr{yn}{10};
    }
    if ( exists $pkg_hr->{'CPMOD'} ) {
        $pkg_hr->{'RS'} ||= delete $pkg_hr->{'CPMOD'};
    }
    if ( exists $pkg_hr->{'LANG'} ) {

        #Be sure we delete the legacy LANG key so that code that iterates
        #through keys doesn't have to accommodate the legacy LANG key.
        my $lang = delete $pkg_hr->{'LANG'};
        if ( !$pkg_hr->{'LOCALE'} ) {
            Cpanel::LoadModule::load_perl_module('Cpanel::Locale::Utils::Legacy');
            $pkg_hr->{'LOCALE'} = Cpanel::Locale::Utils::Legacy::map_any_old_style_to_new_style($lang);
        }
    }
    return;
}

sub change_reseller {
    my ( $oldreseller, $newreseller ) = @_;

    my @PACKAGES;
    my $package_dir = package_dir();
    if ( opendir my $pkgdir_fh, $package_dir ) {
        @PACKAGES = grep /^\Q$oldreseller\E_/, readdir $pkgdir_fh;
        closedir $pkgdir_fh;
    }

    foreach my $pkg (@PACKAGES) {
        my $new_pkg_name = $pkg;
        if ( $new_pkg_name =~ s/^\Q$oldreseller\E_/$newreseller\_/g ) {
            rename_package( $pkg, $new_pkg_name );
        }
    }
}

sub rename_package {
    my ( $source, $target, $overwrite_ok ) = @_;
    $overwrite_ok ||= 0;

    if ( !defined $source || $source eq '' ) {
        logger->warn("source package name missing");
        return;
    }

    if ( !defined $target || $target eq '' ) {
        logger->warn("target package name missing");
        return;
    }

    if ( $source =~ m{(?:\.\.|/)} ) {
        logger->warn("source package name contains path traversing components");
        return;
    }

    if ( $target =~ m{(?:\.\.|/)} ) {
        logger->warn("target package name contains path traversing components");
        return;
    }

    my $package_dir = package_dir();
    if ( !-f "$package_dir$source" ) {
        logger->warn("The package “$source” does not exist.");
        return;
    }

    if ( $source eq $target ) {
        logger->warn("The source and target packages are the same.");
        return;
    }

    if ( -f "$package_dir$target" ) {
        if ($overwrite_ok) {
            if ( !remove_file("$package_dir$target") ) {
                logger->warn("Could not remove “$package_dir$target”: $!");
                return;
            }
        }
        else {
            logger->warn("Can not overwrite package “$target” without specifying it is ok.");
            return;
        }
    }

    # 1. mv $source, $target
    Cpanel::FileUtils::Move::safemv( "$package_dir$source", "$package_dir$target" ) || return;    # safemv() already does errors

    my $user_hr = Whostmgr::AcctInfo::Plans::loaduserplans();
    for my $user ( keys %{$user_hr} ) {
        next if $user_hr->{$user} ne $source;
        $user_hr->{$user} = $target;

        # 2. Update PLAN in $user’s userdata
        my $cpuser_guard = Cpanel::Config::CpUserGuard->new($user);
        next if !$cpuser_guard;
        $cpuser_guard->{'data'}{'PLAN'} = $target;
        if ( !$cpuser_guard->save() ) {
            logger->warn("Changing PLAN to “$target” for “$user” failed.");
            return;
        }
    }

    # 3. save $user_hr to /etc/userplans
    #  - running scripts/updateuserdomains (Cpanel::Userdomains::updateuserdomains()) should not be needed (i.e. it merely creates /etc/userplans if missing)
    #  - Cpanel::TextDB is not used for this file even though that module has that file in an internal list (updateuserdomains does not use this module other),
    #    Cpanel::TextDB appears to be for maanging single entries, not complete rewrites

    my ($header) = @{ Cpanel::LoadFile::loadfileasarrayref($Whostmgr::AcctInfo::Plans::USERPLANS_FILE) || [] };

    my $user_fh;
    my $userlock = Cpanel::SafeFile::safeopen( $user_fh, '>', $Whostmgr::AcctInfo::Plans::USERPLANS_FILE );
    if ($userlock) {
        no strict 'subs';
        no strict 'refs';
        if ( $header =~ m/^#/ ) {
            chomp($header);
            print {$user_fh} "$header\n";
        }

        for my $user ( sort keys %{$user_hr} ) {    # scripts/updateuserdomains does not sort the keys, so apparently order does not matter, but we do it here so its more easily tested
            print {$user_fh} "$user: $user_hr->{$user}\n";
        }
        Cpanel::SafeFile::safeclose( $user_fh, $userlock );
    }
    else {
        logger->warn("Could not open “$Whostmgr::AcctInfo::Plans::USERPLANS_FILE” for writing: $!");
    }

    return 1;
}

sub remove_file {
    my ($file) = @_;
    return unlink $file;
}

1;
