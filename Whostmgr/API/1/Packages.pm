package Whostmgr::API::1::Packages;

# cpanel - Whostmgr/API/1/Packages.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Locale::Maketext::Utils::MarkPhrase;

use Cpanel::ConfigFiles         ();
use Cpanel::Config::CpUserGuard ();
use Cpanel::SafeFile            ();
use Whostmgr::AcctInfo          ();
use Whostmgr::ACLS              ();
use Whostmgr::Packages::Fetch   ();
use Whostmgr::Packages::Find    ();
use Whostmgr::Packages::Load    ();
use Whostmgr::Packages::Mod     ();
use Whostmgr::API::1::Utils     ();

use constant NEEDS_ROLE => {
    addpkg     => undef,
    addpkgext  => undef,
    delpkgext  => undef,
    editpkg    => undef,
    getpkginfo => undef,
    killpkg    => undef,
    listpkgs   => undef,
    matchpkgs  => undef,
};

sub addpkg {
    my ( $args, $metadata ) = @_;
    my ( $result, $reason, %pkg ) = Whostmgr::Packages::Mod::_addpkg(%$args);
    _inject_result_reason_into_metadata( $metadata, $result, $reason );

    # Do not leak an internal notification
    delete $pkg{'exception_obj'} if exists $pkg{'exception_obj'};
    return \%pkg;
}

sub editpkg {
    my ( $args, $metadata ) = @_;
    my ( $result, $reason, %pkg ) = Whostmgr::Packages::Mod::_editpkg(%$args);
    _inject_result_reason_into_metadata( $metadata, $result, $reason );
    return \%pkg;
}

sub killpkg {
    my ( $args, $metadata ) = @_;
    require Whostmgr::Packages;
    my ( $result, $reason ) = Whostmgr::Packages::_killpkg( 'pkg' => $args->{'pkgname'} );
    _inject_result_reason_into_metadata( $metadata, $result, $reason );
    return;
}

sub _inject_result_reason_into_metadata {
    my ( $metadata, $result, $reason ) = @_;
    $metadata->{'result'} = $result ? 1    : 0;
    $metadata->{'reason'} = $result ? 'OK' : $reason;
    return;
}

sub listpkgs {
    my ( $args, $metadata ) = @_;
    require Whostmgr::Packages;
    my @data = Whostmgr::Packages::_listpkgs( %{$args} );
    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    return { 'pkg' => \@data };
}

sub addpkgext {
    my ( $args, $metadata ) = @_;

    return unless ( _valid_package_and_extension( $metadata, $args, '_PACKAGE_EXTENSIONS' ) );

    return _modify_package_extensions( $args, $metadata );
}

sub delpkgext {
    my ( $args, $metadata ) = @_;
    my $args_to_pass = {
        name               => $args->{name},
        _DELETE_EXTENSIONS => $args->{_DELETE_EXTENSIONS}
    };

    return unless ( _valid_package_and_extension( $metadata, $args_to_pass, '_DELETE_EXTENSIONS' ) );

    # Rename arguments for the backend
    $args_to_pass->{remove_missing_extensions} = delete $args_to_pass->{_DELETE_EXTENSIONS};

    return _modify_package_extensions( $args_to_pass, $metadata );
}

sub _valid_package_and_extension {
    my ( $metadata, $args_ref, $extension_name_key ) = @_;

    # Check required arguments
    if ( !defined $args_ref->{name} || $args_ref->{name} =~ /^\s*$/ ) {
        return _argument_error( $metadata, translatable('No package supplied: “[_1]” is a required argument.'), "name" );
    }

    if ( !defined $args_ref->{$extension_name_key} || $args_ref->{$extension_name_key} =~ /^\s*$/ ) {
        return _argument_error( $metadata, translatable('No package extension supplied: “[_1]” is a required argument.'), $extension_name_key );
    }

    if ( defined $args_ref->{remove_missing_extensions} ) {
        return _argument_error( $metadata, translatable('The “[_1]” setting is not allowed.'), 'remove_missing_extensions' );
    }

    # Check all arguments for characters that are not valid in the cpuser file
    foreach my $setting_name ( keys %{$args_ref} ) {
        if ( $setting_name =~ tr/ \n\r\t=#\0// ) {
            return _argument_error( $metadata, translatable('Invalid characters in extension setting name: “[_1]”.'), $setting_name );
        }
        if ( !defined $args_ref->{$setting_name} || $args_ref->{$setting_name} =~ tr/\n\r\0// ) {
            return _argument_error( $metadata, translatable('Invalid extension setting value for “[_1]”.'), $setting_name );
        }
    }

    # Check for authorization to modify the specified package
    my $packages_hr = Whostmgr::Packages::Fetch::fetch_package_list( 'want' => 'editable', package => $args_ref->{name} );
    if ( !exists $packages_hr->{ $args_ref->{name} } ) {
        return _argument_error( $metadata, translatable('The package name “[_1]” does not refer to an existing package you are authorized to edit.'), $args_ref->{name} );
    }
    return 1;
}

sub _argument_error {
    my ( $metadata, $error_message, @args ) = @_;
    require Cpanel::Locale;
    my $locale = Cpanel::Locale->get_handle();
    $metadata->{'result'} = 0;
    $metadata->{'reason'} = $locale->maketext( $error_message, @args );    ## no extract maketext
    return 0;
}

sub _modify_package_extensions {
    my ( $args, $metadata ) = @_;
    my $package = $args->{'name'};

    my $pkg_info = Whostmgr::Packages::Load::load_package( $package, $metadata, 0 );
    return unless $metadata->{'result'};

    my %target_config = %$pkg_info;
    my $return_msg    = Whostmgr::Packages::Mod::_add_or_remove_pkgext( $pkg_info, \%target_config, $args, 1 );

    if ($return_msg) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $return_msg;
        return;
    }

    my $package_dir = "$Cpanel::ConfigFiles::PACKAGES_DIR/";

    my $pkglock = Cpanel::SafeFile::safeopen( \*PKG, '>', $package_dir . $package );
    if ( !$pkglock ) {
        require Cpanel::Locale;
        my $locale = Cpanel::Locale->get_handle();
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $locale->maketext( 'Could not edit “[_1]”.', $package_dir . $package );
        return;
    }
    foreach my $pkgitem ( sort keys %target_config ) {
        next if !$pkgitem;
        next if ( $pkgitem eq '_PACKAGE_EXTENSIONS' );
        my $line = qq{$pkgitem=$target_config{$pkgitem}};
        $line =~ s/[\r\n]//g;
        print PKG $line . "\n";
    }
    print PKG qq{_PACKAGE_EXTENSIONS=$target_config{_PACKAGE_EXTENSIONS}\n};    # _PACKAGE_EXTENSIONS last in file.
    Cpanel::SafeFile::safeclose( \*PKG, $pkglock );

    # Modify accounts the reseller has access to that use this package.
    my %ACCTS = Whostmgr::AcctInfo::acctlister( $package, ( Whostmgr::ACLS::hasroot() ? () : ( $ENV{REMOTE_USER} ) ) );
    foreach my $user ( sort keys %ACCTS ) {
        my $cpuser_guard = Cpanel::Config::CpUserGuard->new($user);

        if ( !$cpuser_guard ) {
            $metadata->{'result'} = 0;
            $metadata->{'reason'} = "User $user has no cPanel users configuration file";
            return;
        }

        my $cpuser_ref = $cpuser_guard->{'data'};

        my %new_config = %$cpuser_ref;
        my $return_msg = Whostmgr::Packages::Mod::_add_or_remove_pkgext( $cpuser_ref, \%new_config, $args, 1 );

        if ($return_msg) {
            $metadata->{'result'} = 0;
            $metadata->{'reason'} = $return_msg;
            return;
        }

        $cpuser_guard->{'data'} = \%new_config;
        $cpuser_guard->save();
    }

    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';

    return { 'pkg' => $package };
}

sub getpkginfo {
    my ( $args, $metadata ) = @_;
    my $pkg_info = Whostmgr::Packages::Load::load_package( $args->{'pkg'}, $metadata, 1 );

    return unless $metadata->{'result'};

    for my $key (qw(BWLIMIT MAXFTP MAXADDON MAXLST MAXPARK MAXPOP MAXSQL MAXSUB QUOTA MAXTEAMUSERS)) {
        if ( !( defined $pkg_info->{$key} ) || $pkg_info->{$key} =~ m{\Aunlimited\z}i ) {
            $pkg_info->{$key} = undef;
        }
    }
    for my $key (qw(CGI HASSHELL IP)) {
        $pkg_info->{$key} = ( $pkg_info->{$key} && $pkg_info->{$key} =~ tr{yY1}{} ) ? 1 : 0;
    }

    $pkg_info->{'FRONTPAGE'} = 0;

    return { 'pkg' => $pkg_info };
}

sub matchpkgs {
    my ( $args, $metadata ) = @_;
    my $user    = $args->{'USER'} || $args->{'user'};
    my $want    = $args->{'want'};
    my $exclude = $args->{'exclude'};
    my $pkgs_ar = Whostmgr::Packages::Find::find_matching_packages(
        'user' => $user,
        ( $exclude ? ( 'current_package' => $exclude ) : () ),
        ( $want    ? ( 'want'            => $want )    : () ),
        'settings' => $args,
    );
    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';
    return { 'pkg' => $pkgs_ar };
}

1;
