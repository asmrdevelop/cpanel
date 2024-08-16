package Whostmgr::Packages::Mod;

# cpanel - Whostmgr/Packages/Mod.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings)

use experimental 'signatures';

use Cpanel::AcctUtils::Owner          ();
use Cpanel::DIp::MainIP               ();
use Cpanel::Encoder::Tiny             ();
use Cpanel::Exception                 ();
use Cpanel::FileUtils::TouchFile      ();
use Cpanel::Hooks                     ();
use Cpanel::LoadModule                ();
use Cpanel::Locale::Utils::Display    ();
use Cpanel::SafeFile                  ();
use Cpanel::StringFunc::Trim          ();
use Cpanel::Team::Constants           ();
use Cpanel::Validate::PackageName     ();
use Whostmgr::ACLS                    ();
use Whostmgr::Accounts::Abilities     ();
use Whostmgr::Accounts::Shell         ();
use Whostmgr::Func                    ();
use Whostmgr::Packages::Fetch         ();
use Whostmgr::Packages::Info          ();
use Whostmgr::Packages::Load          ();
use Whostmgr::Packages::Info::Modular ();

use Cpanel::LinkedNode::Worker::WHM::Packages ();

use Cpanel::Imports;

sub _addpkg {
    my %OPTS = @_;
    delete $OPTS{'edit'};
    return _modpkg(%OPTS);
}

sub _editpkg {
    my %OPTS = @_;
    $OPTS{'edit'} = 'yes';
    return _modpkg(%OPTS);
}

sub _modpkg {    ## no critic qw(Subroutines::ProhibitExcessComplexity Subroutines::RequireArgUnpacking)
    my %OPTS;
    if ( ref $_[0] eq 'HASH' ) {
        %OPTS = %{ $_[0] };
    }
    else {
        %OPTS = @_;
    }

    local $@;
    require Cpanel::LinkedNode::Worker::WHM::Packages;
    my @return = eval { Cpanel::LinkedNode::Worker::WHM::Packages::create_or_update_package( \%OPTS ) };

    if ($@) {
        return wantarray ? ( 0, $@, exception_obj => $@ ) : 0;
    }

    return wantarray ? @return : $return[0];
}

# This function expects to receive either a hash or hashref of the package options.
# In scalar context, it outputs 1 or 0 to indicate the success or failure of the calls.
# In list context, it outputs the status, a message describing the success or failure, and a
#   variable set of key/value pairs.
sub __modpkg {    ## no critic qw(Subroutines::ProhibitExcessComplexity Subroutines::RequireArgUnpacking)
    my %OPTS;
    if ( ref $_[0] eq 'HASH' ) {
        %OPTS = %{ $_[0] };
    }
    else {
        %OPTS = @_;
    }

    # Detect package name before lowercasing process.
    # Make package name detection more consistent with other code paths.
    # See SEC-557

    my $name;

    {
        local $@;
        eval { $name = Cpanel::LinkedNode::Worker::WHM::Packages::get_pkgname_from_package_settings( \%OPTS ); } or do {
            logger->info('No package supplied: "pkgname" or "name" is a required argument.');
            return wantarray ? ( 0, locale->maketext( 'No package supplied: “[_1]” or “[_2]” is a required argument.', 'pkgname', 'name' ) ) : 0;
        };
    }

    # all values should be lowercase except _PACKAGE_EXTENSIONS
    # we are going to keep both values if an extension use a key with uppercase
    my $space_delimited_PACKAGE_EXTENSIONS;
    foreach my $k ( keys %OPTS ) {

        # Collapse multiple params down into one (Cpanel::Form does multiple ones in a non-standard way)
        if ( $k =~ m/^_PACKAGE_EXTENSIONS(?:-\d+)?$/ ) {
            $space_delimited_PACKAGE_EXTENSIONS .= ' ' . delete $OPTS{$k};
            next;    # only value which is not lowercased
        }

        my $lck = lc($k);

        # Remove any extra name or pkgname keys that snuck in, we already determined the name.

        if ( ( $lck eq 'pkgname' ) or ( $lck eq 'name' ) ) {
            delete $OPTS{$k};
            next;
        }

        if ( $k eq $lck ) {
            next;
        }
        else {
            $OPTS{$lck} = $OPTS{$k};
        }
    }

    $OPTS{'name'} = $name;
    $name = _get_package_name_for_user($name);

    {
        local $@;
        eval { Cpanel::Validate::PackageName::validate_or_die($name) } or do {
            return wantarray ? ( 0, $@->to_locale_string() ) : 0;
        };
    }

    if ( defined $space_delimited_PACKAGE_EXTENSIONS ) {
        $OPTS{'_PACKAGE_EXTENSIONS'} = Cpanel::StringFunc::Trim::ws_trim($space_delimited_PACKAGE_EXTENSIONS);
    }

    # This subroutine is needed when called from modaccount, also now used in Whostmgr::Packages::Restore::create_package_from_cpuser_data
    convert_cpuser_to_package_keys( \%OPTS );

    # For the most part, convert modaccount/create_package_from_cpuser_data passed uppercase keys to lowercase.
    convert_package_hr_to_lowercase( \%OPTS );

    # Feature List names are stored as being HTML encoded
    if ( defined $OPTS{'featurelist'} ) {
        $OPTS{'featurelist'} = Cpanel::Encoder::Tiny::safe_html_encode_str( $OPTS{'featurelist'} );
    }

    my ( $is_valid, $validate_msg ) = Whostmgr::Packages::Info::validate_package_options( \%OPTS );
    if ( !$is_valid ) {
        return wantarray ? ( $is_valid, $validate_msg ) : $is_valid;
    }

    # Strip commas since commas will break the whole system
    # Parse out custom attributes and insert in hash for writing
    foreach my $opt ( keys %OPTS ) {
        $OPTS{$opt} =~ s/\,//g;
    }

    my $package_dir = Whostmgr::Packages::Load::package_dir();
    if ( -e $package_dir . $name && ( !defined $OPTS{'edit'} || $OPTS{'edit'} ne 'yes' ) ) {
        ####################################################################
        #
        # If this failure reason or error reporting technique is ever modified,
        # please update Whostmgr::Packages::Restore::create_package_from_cpuser_data to check for the new message/technique.
        #
        my $message = locale->maketext( 'The package “[_1]” already exists. If you wish to make changes, please edit the package.', $name );
        return wantarray ? ( 0, $message, 'exception_obj' => Cpanel::Exception::create_raw( 'HostingPackage::AlreadyExists', $message ) ) : 0;
    }

    if ( !Whostmgr::ACLS::hasroot() ) {
        my $pkglist_ref = Whostmgr::Packages::Fetch::fetch_package_list( 'want' => 'viewable', package => $name );
        if ( defined $OPTS{'edit'} && $OPTS{'edit'} eq 'yes' && !$pkglist_ref->{$name} ) {
            logger->info('_modpkg requires a package name that you have permission to access.');
            return wantarray ? ( 0, locale->maketext( '“[_1]” requires a package name that you have permission to access.', '_modpkg' ) ) : 0;
        }
        require Whostmgr::Resellers::Pkg;
        Whostmgr::Resellers::Pkg::add_pkg_permission( $ENV{'REMOTE_USER'}, $name );
    }

    # After validation is done, load any values from the old package in to ensure they're not clobbered
    # Only attempt to load when editing an existing package and not creating a new package
    my $original = {};
    if ( defined $OPTS{'edit'} && $OPTS{'edit'} eq 'yes' ) {
        $original = Whostmgr::Packages::Load::load_package($name);
        foreach my $key ( keys %{$original} ) {
            $OPTS{ lc $key } = $original->{$key} if !exists $OPTS{ lc $key };
        }
    }

    my %defaults = Whostmgr::Packages::Info::get_defaults();

    my @validation_errors;

    # We used to massage the quota/bwlimit values so that users without the appropriate allow-unlimited-* ACL would get a quota of 1 if they specified 0 or a string.
    # Now we reject 0, unlimited, or an empty string as invalid if they don't have the appropriate ACL.
    my ( $quota, $quota_error ) = _determine_actual_value( "quota", $OPTS{'quota'}, "allow-unlimited-disk-pkgs", $defaults{'quota'}{'limited_default'}, $original->{'QUOTA'} );
    push @validation_errors, $quota_error if defined $quota_error;

    my ( $bwlimit, $bwlimit_error ) = _determine_actual_value( "bwlimit", $OPTS{'bwlimit'}, "allow-unlimited-bw-pkgs", $defaults{'bwlimit'}{'limited_default'}, $original->{'BWLIMIT'} );
    push @validation_errors, $bwlimit_error if defined $bwlimit_error;

    my ( $max_emailacct_quota, $max_emailacct_quota_error ) = _determine_actual_value( "max_emailacct_quota", $OPTS{'max_emailacct_quota'}, "allow-unlimited-pkgs", $defaults{'max_emailacct_quota'}{'limited_default'}, $original->{'MAX_EMAILACCT_QUOTA'} );
    push @validation_errors, $max_emailacct_quota_error if defined $max_emailacct_quota_error;

    my $cgi = Whostmgr::Func::yesno( $OPTS{'cgi'} );

    my $hasshell = 'no';
    if ( Whostmgr::ACLS::checkacl('add-pkg-shell') ) {
        $hasshell = Whostmgr::Func::yesno( $OPTS{'hasshell'} );
    }
    else {
        $hasshell = Whostmgr::Func::yesno(0);
    }

    if ( !Whostmgr::Accounts::Abilities::new_account_can_have_cgi() && $cgi ne 'n' ) {
        push @validation_errors, "This server cannot give CGI access.";
    }

    if ( !Whostmgr::Accounts::Abilities::new_account_can_have_shell() && $hasshell ne 'n' ) {
        push @validation_errors, "This server cannot give shell access.";
    }

    if (@validation_errors) {
        return wantarray ? ( 0, join( "\n", @validation_errors, q<> ) ) : 0;
    }

    my $ip;

    if ( Whostmgr::ACLS::checkacl('add-pkg-ip') ) {
        $ip = Whostmgr::Func::yesno( $OPTS{'ip'} );
    }
    else {
        $ip = Whostmgr::Func::yesno(0);
    }

    my $digestauth = Whostmgr::Func::yesno( $OPTS{'digestauth'} );

    my $maxftp = _enforce_limits( $OPTS{'maxftp'}, $original->{'MAXFTP'}, 'allow-unlimited-pkgs' );
    my $maxsql = _enforce_limits( $OPTS{'maxsql'}, $original->{'MAXSQL'}, 'allow-unlimited-pkgs' );
    my $maxpop = _enforce_limits( $OPTS{'maxpop'}, $original->{'MAXPOP'}, 'allow-unlimited-pkgs' );
    my $maxlst = _enforce_limits( $OPTS{'maxlst'}, $original->{'MAXLST'}, 'allow-unlimited-pkgs' );
    my $maxsub = _enforce_limits( $OPTS{'maxsub'}, $original->{'MAXSUB'}, 'allow-unlimited-pkgs' );

    my $max_team_users = $OPTS{'max_team_users'} // $Cpanel::Team::Constants::MAX_TEAM_USERS_WITH_ROLES;

    my $maxpassengerapps = _enforce_limits( $OPTS{'maxpassengerapps'}, $original->{'MAXPASSENGERAPPS'}, 'allow-unlimited-pkgs' );

    my $maxpark  = Whostmgr::ACLS::checkacl('allow-parkedcreate') ? _enforce_limits( $OPTS{'maxpark'},  $original->{'MAXPARK'},  'allow-unlimited-pkgs' ) : 0;
    my $maxaddon = Whostmgr::ACLS::checkacl('allow-addoncreate')  ? _enforce_limits( $OPTS{'maxaddon'}, $original->{'MAXADDON'}, 'allow-unlimited-pkgs' ) : 0;

    my $maxemailsperhour                            = _enforce_limits( $OPTS{'max_email_per_hour'},        $original->{'MAX_EMAIL_PER_HOUR'},        'allow-emaillimits-pkgs' );
    my $email_send_limits_max_defer_fail_percentage = _enforce_limits( $OPTS{'max_defer_fail_percentage'}, $original->{'MAX_DEFER_FAIL_PERCENTAGE'}, 'allow-emaillimits-pkgs' );

    my $featurelist = defined $OPTS{'featurelist'} ? $OPTS{'featurelist'} : 'default';

    ########################################################################################
    # Hook for 3rd party to verify/process the input given to WHM API for custom packages

    my $hook_info = {
        'category' => 'Whostmgr',
        'event'    => 'Packages::verify_input_data',
        'stage'    => 'pre',
        'blocking' => 1,
    };

    my ( $pre_hook_result, $hook_msgs ) = Cpanel::Hooks::hook(
        $hook_info,
        \%OPTS
    );
    return ( 0, Cpanel::Hooks::hook_halted_msg( $hook_info, $hook_msgs ) ) if !$pre_hook_result;

    if ( !-e $package_dir . $name ) {
        Cpanel::FileUtils::TouchFile::touchfile( $package_dir . $name );
    }

    my %PKG_CONFIG;

    $PKG_CONFIG{'QUOTA'} = $quota;

    #Note: backend function allows changing package IP setting,
    #while frontend disallows it.
    $PKG_CONFIG{'IP'} = $ip;

    $PKG_CONFIG{'DIGESTAUTH'}          = $digestauth;
    $PKG_CONFIG{'CGI'}                 = $cgi;
    $PKG_CONFIG{'MAXFTP'}              = $maxftp;
    $PKG_CONFIG{'MAXSQL'}              = $maxsql;
    $PKG_CONFIG{'MAXPOP'}              = $maxpop;
    $PKG_CONFIG{'MAXLST'}              = $maxlst;
    $PKG_CONFIG{'MAXSUB'}              = $maxsub;
    $PKG_CONFIG{'MAXPASSENGERAPPS'}    = $maxpassengerapps;
    $PKG_CONFIG{'MAXPARK'}             = $maxpark;
    $PKG_CONFIG{'MAXADDON'}            = $maxaddon;
    $PKG_CONFIG{'MAX_TEAM_USERS'}      = $max_team_users;
    $PKG_CONFIG{'FEATURELIST'}         = $featurelist;
    $PKG_CONFIG{'MAX_EMAILACCT_QUOTA'} = $max_emailacct_quota;

    for my $component ( Whostmgr::Packages::Info::Modular::get_enabled_components() ) {
        my $value = $OPTS{ $component->name_in_api() };
        $value //= $component->default();

        $PKG_CONFIG{ $component->name_in_package() } = $value;
    }

    $PKG_CONFIG{'BWLIMIT'}  = $bwlimit;
    $PKG_CONFIG{'HASSHELL'} = $hasshell;
    if ( defined $maxemailsperhour ) {
        $PKG_CONFIG{'MAX_EMAIL_PER_HOUR'} = $maxemailsperhour;
    }

    if ( defined $email_send_limits_max_defer_fail_percentage ) {
        $PKG_CONFIG{'MAX_DEFER_FAIL_PERCENTAGE'} = $email_send_limits_max_defer_fail_percentage;
    }

    if ( exists $OPTS{'lang'} ) {
        $PKG_CONFIG{'LANG'} = $OPTS{'lang'};
    }

    # Setting/Modifying Package locale:
    # Verify package definition if locale not specified.
    # Verify locale argument and only update package when valid.
    my $language_for_locale = Cpanel::Locale::Utils::Display::get_locale_menu_hashref(locale);

    # Open existing file, creating as necessary
    my $pkglock = Cpanel::SafeFile::safeopen( \*PKG, '+<', $package_dir . $name );
    if ( !$pkglock ) {
        logger->warn("Could not edit ${package_dir}$name");
        return wantarray ? ( 0, locale->maketext( 'Could not edit “[_1]”.', "${package_dir}$name" ) ) : 0;
    }

    # Slurp existing file
    my %OLD_PKG_CONFIG;
    {
        local $/;
        %OLD_PKG_CONFIG = map { m{\S} ? ( split( /\s*=\s*/, $_, 2 ) )[ 0, 1 ] : () } split( /[\r\n]+/, readline( \*PKG ) );
    };

    # Apply cPanel default theme
    # If empty value is provided during 'Add Package'
    # OR
    # During edit package: if a package's cpmod is empty and empty value is provided as argument.
    if ( defined $OPTS{'edit'} && $OPTS{'edit'} eq 'yes' ) {
        $PKG_CONFIG{'CPMOD'} = $OLD_PKG_CONFIG{'CPMOD'};

        if ( !exists $OPTS{'cpmod'}
            || ( exists $OPTS{'cpmod'} && $OPTS{'cpmod'} eq '' ) ) {    # cpmod is explicitly set to empty
            if ( !$PKG_CONFIG{'CPMOD'} ) {
                $PKG_CONFIG{'CPMOD'} = $defaults{'cpmod'}{'default'};
            }
        }
        elsif ( exists $OPTS{'cpmod'} && $OPTS{'cpmod'} ) {
            $PKG_CONFIG{'CPMOD'} = $OPTS{'cpmod'};
        }
    }
    else {
        $PKG_CONFIG{'CPMOD'} = $OPTS{'cpmod'} || $defaults{'cpmod'}{'default'};
    }

    if ( !$OPTS{'language'} ) {
        if ( !$PKG_CONFIG{'LANG'} ) {
            $PKG_CONFIG{'LANG'} = 'en';
        }
        elsif ( !exists $language_for_locale->{ $PKG_CONFIG{'LANG'} } ) {
            logger->warn("Resetting package $name language definition to 'en': Invalid locale specified (not available via locale system).");
            $PKG_CONFIG{'LANG'} = 'en';
        }
    }
    else {
        if ( !exists $language_for_locale->{ $OPTS{'language'} } ) {
            logger->warn("Invalid language specified as an argument.");
            if ( $PKG_CONFIG{'LANG'} ) {
                if ( !exists $language_for_locale->{ $PKG_CONFIG{'LANG'} } ) {
                    logger->warn("Resetting package $name language definition to 'en'. Invalid locale specified in package (not available via locale system).");
                    $PKG_CONFIG{'LANG'} = 'en';
                }
            }
            else {
                $PKG_CONFIG{'LANG'} = 'en';
            }
        }
        else {
            $PKG_CONFIG{'LANG'} = $OPTS{'language'};
        }
    }

    my $return_msg = _add_or_remove_pkgext( \%OLD_PKG_CONFIG, \%PKG_CONFIG, \%OPTS, 0 );

    if ($return_msg) {
        Cpanel::SafeFile::safeclose( \*PKG, $pkglock );
        return wantarray ? ( 0, $return_msg ) : 0;
    }

    # Look for any custom attributes, if not set, keep old value, otherwise, use new one
    foreach my $customitem ( keys %OLD_PKG_CONFIG ) {
        my $opts_key = lc($customitem);
        if ( !exists $OPTS{$opts_key} && !exists $PKG_CONFIG{$customitem} ) {
            $PKG_CONFIG{$customitem} = $OLD_PKG_CONFIG{$customitem};
            $PKG_CONFIG{$customitem} =~ s/\,//g;    # apparently, commas in value are bad? see begin of subroutine
        }
        elsif ( exists $OPTS{$opts_key} && !exists $PKG_CONFIG{$customitem} ) {
            $PKG_CONFIG{$customitem} = $OPTS{$opts_key};
            $PKG_CONFIG{$customitem} =~ s/\,//g;    # apparently, commas in value are bad? see begin of subroutine
        }
    }

    my $had_changes;

    seek( PKG, 0, 0 );
    foreach my $pkgitem ( sort keys %PKG_CONFIG ) {
        next if !$pkgitem;
        next if ( $pkgitem eq '_PACKAGE_EXTENSIONS' );
        my $line = qq{$pkgitem=$PKG_CONFIG{$pkgitem}};
        $line =~ s/[\r\n]//g;
        print PKG $line . "\n";

        # Look for things that the old package settings didn’t have or that changed
        $had_changes = 1 if !exists $OLD_PKG_CONFIG{$pkgitem} || $OLD_PKG_CONFIG{$pkgitem} ne $PKG_CONFIG{$pkgitem};
    }
    print PKG qq{_PACKAGE_EXTENSIONS=$PKG_CONFIG{_PACKAGE_EXTENSIONS}\n};    # _PACKAGE_EXTENSIONS last in file.
    truncate( PKG, tell(PKG) );
    Cpanel::SafeFile::safeclose( \*PKG, $pkglock );

    if ( exists $OLD_PKG_CONFIG{_PACKAGE_EXTENSIONS} ) {

        # Package extensions existed in the old config and were different than the new settings
        $had_changes = 1 if $OLD_PKG_CONFIG{_PACKAGE_EXTENSIONS} ne $PKG_CONFIG{_PACKAGE_EXTENSIONS};
    }
    else {

        # Package extensions didn’t exist in the old config but new extensions were added
        $had_changes = 1 if $PKG_CONFIG{_PACKAGE_EXTENSIONS};
    }

    if ( !$had_changes && keys %OLD_PKG_CONFIG ) {

        # Look for things the old package settings had that the new ones don’t
        foreach my $pkgitem ( keys %OLD_PKG_CONFIG ) {
            if ( !exists $PKG_CONFIG{$pkgitem} ) {
                $had_changes = 1;
                last;
            }
        }
    }

    if ( defined $OPTS{'edit'} && $OPTS{'edit'} eq 'yes' ) {

        # Avoid expensive actions when nothing in the package actually changed
        _perform_post_package_change_actions($name) if $had_changes;
        return wantarray ? ( 1, locale->maketext( 'You have successfully modified the package “[_1]”.', $name ), 'pkg' => $name ) : 1;

    }
    else {
        return wantarray ? ( 1, locale->maketext( 'You have successfully created the package “[_1]”.', $name ), 'pkg' => $name ) : 1;
    }
}

sub _perform_post_package_change_actions {

    my ($name) = @_;

    my $accts_owner = $ENV{REMOTE_USER};

    # URI-escape so that package names with spaces don’t mess up
    # the task queue, which expects all args to be space-separated.
    require Cpanel::Encoder::URI;
    my $name_uri = Cpanel::Encoder::URI::uri_encode_str($name);

    require Cpanel::ServerTasks;
    Cpanel::ServerTasks::schedule_tasks( ['AccountTasks'], [ [ "apply_package_to_accounts $name_uri $accts_owner", {} ] ] );

    return;
}

sub _get_package_name_for_user {
    my ($name) = @_;

    if ( !Whostmgr::ACLS::hasroot() ) {
        my $reseller = $ENV{'REMOTE_USER'};
        $name =~ s/^\Q$reseller\E_//g;
        $name = $reseller . '_' . $name;
    }

    return $name;
}

###########################################################################
#
# Method:
#   _add_or_remove_pkgext
#
# Description:
#   This function modifies a passed-in user or package configuration, to
#   add or update information on package extensions. It may be used for
#   package configs, or user configs! The configurations and options are
#   passed by reference, so they are modified in-place!
#
# Parameters:
#   $original_config - The previous version of the configuration that
#                      is being modified.
#   $target_config   - The new configuration that is being constructed.
#   $options         - Desired modifications to the configuration (i.e.
#                      what changes have been requested by the API or other
#                      caller
#   $keep_original   - Boolean. On truth, package extensions from the
#                      original configuration will be copied into the
#                      target. This allows override of the existing
#                      behavior of _modpkg, which always overwrote
#                      package extensions.
#
# Exceptions:
#   None thrown
#
# Returns:
#   The method returns undef on success or a localized message describing
#   failure.
#
sub _add_or_remove_pkgext {
    my ( $original_config, $target_config, $options, $keep_original ) = @_;

    # Process package extensions submitted if the package is on.
    my $extensions_dir = Whostmgr::Packages::Load::package_extensions_dir();
    my @supported_extensions;
    my %candidate_extensions;

    if ( exists $options->{'_PACKAGE_EXTENSIONS'} ) {
        foreach my $ext ( split /\s+/, $options->{'_PACKAGE_EXTENSIONS'} || '' ) {
            $candidate_extensions{$ext} = 1;
        }
    }

    if ( $keep_original || !exists $options->{'_PACKAGE_EXTENSIONS'} ) {

        # We're forcing an add here, or _PACKAGE_EXTENSIONS was not given so keep the current one if there are any
        if ( exists $original_config->{'_PACKAGE_EXTENSIONS'} ) {
            foreach my $ext ( split /\s+/, $original_config->{'_PACKAGE_EXTENSIONS'} || '' ) {
                $candidate_extensions{$ext} = 1;
            }
        }
    }

    # It's possible, if the keep_original flag is misused, to end up with duplicates in the array, so this dedupes.
    @supported_extensions = keys %candidate_extensions;

    # remove missing package extensions from _PACKAGE_EXTENSIONS
    # if user so desires
    if ( exists $options->{'remove_missing_extensions'} ) {
        foreach my $missing_ext ( split( /\s+/, $options->{'remove_missing_extensions'} ) ) {
            @supported_extensions = grep { $_ ne $missing_ext } @supported_extensions;
        }
    }

    for my $ext (@supported_extensions) {
        if ( $ext =~ m{(?:/|\.\.|[^\w\.\-\s\_])} ) {
            logger->warn("Package extension value is invalid ($ext).");

            # do not include $ext in output in case its XSS, HTML encode first? sure, but then it'd look weird via CLI. defer for now
            return locale->maketext('Package extension value is invalid.');
        }
    }

    # pull in variables from extension file or old package file if not submitted to
    # subroutine
    foreach my $extension (@supported_extensions) {
        my $extension_defaults = Whostmgr::Packages::Load::load_package_file_raw("${extensions_dir}$extension");
        foreach my $extension_var ( keys %$extension_defaults ) {
            next if ( $extension_var eq '_NAME' );    # This is for display, we never save this.
            $target_config->{$extension_var} =
                defined( $options->{$extension_var} )         ? $options->{$extension_var}
              : defined( $original_config->{$extension_var} ) ? $original_config->{$extension_var}
              :                                                 $extension_defaults->{$extension_var};
        }
    }
    $target_config->{'_PACKAGE_EXTENSIONS'} = join( ' ', sort @supported_extensions );

    # Delete removed package extension variables
    my %old_extensions = map { ( $_ => 1 ) } split( /\s+/, $original_config->{'_PACKAGE_EXTENSIONS'} || '' );
    delete $old_extensions{$_} for (@supported_extensions);
    foreach my $removed_extension ( keys %old_extensions ) {
        my $extension_defaults = Whostmgr::Packages::Load::load_package_file_raw("${extensions_dir}$removed_extension");
        delete $original_config->{$_} for ( keys %$extension_defaults );
        delete $target_config->{$_}   for ( keys %$extension_defaults );
    }

    return undef;
}

###########################################################################
#
# Method:
#   _determine_actual_value
#
# Description:
#   Determines the value of a plan based upon what is supplied by the user.
#
#   Any reseller without the specified ACL may only have a numeric setting in their
#   packages. Any reseller with the ACL (or higher), may have an 'unlimited' quota
#   setting and 'unlimited' is the default value. In both cases, the lowest numeric
#   value is '1'.
#
# TODO: This duplicates and may conflict with
# Whostmgr::Packages::Info::validate_package_options().
#
# Parameters:
#   $package_field - string - The field in the plan the value is for
#   $passed_in_value - string - The value supplied by the user
#   $unlimited_acl - string - The ACL to apply when considering unlimited values
#   $limited_default - number - The default value to use if no value is supplied by the user and the user doesn't have the unlimited ACL
#
# Returns
#   value - integer or unlimited - The plan value, potentially modified from the passed in value
#   error - string - An error string if the provided value fails validation
sub _determine_actual_value {
    my ( $package_field, $passed_in_value, $unlimited_acl, $limited_default, $original_value ) = @_;
    if ( !defined($original_value) ) { $original_value = ""; }

    # Reject 0 and non-numeric values that aren't "unlimited"
    if ( defined $passed_in_value && "$passed_in_value" ne "unlimited" && "$passed_in_value" ne "" && ( $passed_in_value !~ /\A[0-9]+\z/ || $passed_in_value == 0 ) ) {
        return wantarray ? ( undef, locale->maketext( "Invalid value “[_1]” for the “[_2]” setting.", $passed_in_value // "", $package_field ) . "\n" ) : undef;
    }
    elsif ( !Whostmgr::ACLS::checkacl($unlimited_acl) ) {
        if ( !defined $passed_in_value || "$passed_in_value" eq "" ) {
            return wantarray ? ( $limited_default, undef ) : undef;
        }
        elsif ( ( "$passed_in_value" eq "unlimited" ) && ( $original_value ne "unlimited" ) ) {
            return wantarray ? ( undef, locale->maketext( "Invalid value “[_1]” for the “[_2]” setting.", $passed_in_value, $package_field ) . "\n" ) : undef;
        }
    }
    elsif ( !defined $passed_in_value || "$passed_in_value" eq "" ) {
        return wantarray ? ( "unlimited", undef ) : "unlimited";
    }

    return wantarray ? ( $passed_in_value, undef ) : $passed_in_value;
}

sub _enforce_limits {
    my ( $value, $old_value, $acl ) = @_;
    $value = Whostmgr::Func::unlimitedint($value);
    if ( !defined $old_value )                     { $old_value = ''; }
    if ( $value eq '' || $value =~ m/unlimited/i ) { $value     = 'unlimited'; }
    if ( Whostmgr::ACLS::checkacl($acl) )          { return $value; }
    if ( $value eq 'unlimited' ) {
        $value = ( $old_value eq 'unlimited' ) ? 'unlimited' : '0';
    }
    return $value;
}

#_addpkg() and _editpkg() aka _modpkg() expect lower-case keys and are passed them by cpanel forms.
# So this code has no effect for cPanel forms. This possibly helps xml-api callers passing capitolized variables.
sub convert_package_hr_to_lowercase {
    my $hash_ref = shift or return;

    if ( exists $hash_ref->{'LANG'} ) {
        $hash_ref->{'language'} = delete $hash_ref->{'LANG'};
    }

    #lower-case the keys in $cpuser_hr
    for my $key (
        qw/BWLIMIT CGI CPMOD DIGESTAUTH FEATURELIST HASSHELL IP LANGUAGE MAX_DEFER_FAIL_PERCENTAGE
        MAX_EMAIL_PER_HOUR MAXADDON MAXFTP MAXLST MAXPARK MAXPOP MAXSQL MAXSUB NAME RS QUOTA MAX_EMAILACCT_QUOTA/
    ) {
        next if ( !exists $hash_ref->{$key} || !$hash_ref->{$key} );

        $hash_ref->{ lc $key } = delete $hash_ref->{$key};
    }

    return $hash_ref;
}

#_addpkg() and _editpkg() expect lower-case keys,
#but they write upper-case keys in the package file.
sub convert_cpuser_to_package_keys {
    my $cpuser_hr = shift;

    #simple conversions
    if ( exists $cpuser_hr->{'BWLIMIT'} && $cpuser_hr->{'BWLIMIT'} !~ m{\D} ) {
        $cpuser_hr->{'BWLIMIT'} /= 1024 * 1024;
    }
    if ( exists $cpuser_hr->{'QUOTA'} && $cpuser_hr->{'QUOTA'} !~ m{\D} ) {
        $cpuser_hr->{'QUOTA'} /= 1024 * 1024;
    }
    if ( exists $cpuser_hr->{'HASCGI'} ) {
        $cpuser_hr->{'CGI'} = delete $cpuser_hr->{'HASCGI'};
        $cpuser_hr->{'CGI'} =~ tr{10}{yn};
    }
    if ( exists $cpuser_hr->{'RS'} ) {
        $cpuser_hr->{'CPMOD'} = delete $cpuser_hr->{'RS'};
    }

    #account options not stored in the cpuser file
    if ( !exists( $cpuser_hr->{'HASSHELL'} ) ) {
        if ( defined $cpuser_hr->{'shell'} ) {
            $cpuser_hr->{'HASSHELL'} = Whostmgr::Func::yesno( delete $cpuser_hr->{'shell'} );
        }
        elsif ( defined $cpuser_hr->{'USER'} ) {
            $cpuser_hr->{'HASSHELL'} = 'n';
            if ( Whostmgr::Accounts::Shell::has_unrestricted_shell( $cpuser_hr->{'USER'} ) || Whostmgr::Accounts::Shell::has_jail_shell( $cpuser_hr->{'USER'} ) ) {
                $cpuser_hr->{'HASSHELL'} = 'y';
            }
        }
    }
    else {
        $cpuser_hr->{'HASSHELL'} =~ tr{10}{yn};
    }
    if ( !exists( $cpuser_hr->{'QUOTA'} ) && defined( $cpuser_hr->{'USER'} ) ) {
        Cpanel::LoadModule::load_perl_module('Cpanel::Quota');
        my @used_limit_remain = Cpanel::Quota::displayquota(
            {
                user            => $cpuser_hr->{'USER'},
                bytes           => 1,
                include_sqldbs  => 0,
                include_mailman => 0,
            }
        );
        $cpuser_hr->{'QUOTA'} = ( 0 + ( $used_limit_remain[1] || 0 ) ) || 'unlimited';
    }

    if ( defined( $cpuser_hr->{'IP'} ) && $cpuser_hr->{'IP'} !~ m{\A[yn]\z}i ) {
        my $owner = $cpuser_hr->{'OWNER'};
        if ( !$owner && defined $cpuser_hr->{'USER'} ) {
            $owner = Cpanel::AcctUtils::Owner::getowner( $cpuser_hr->{'USER'} );
        }
        my $shared_ip;
        if ($owner) {
            require Whostmgr::Resellers::Ips;
            $shared_ip = Whostmgr::Resellers::Ips::get_reseller_mainip($owner);
        }
        $shared_ip ||= Cpanel::DIp::MainIP::getmainserverip();

        $cpuser_hr->{'IP'} = ( $cpuser_hr->{'IP'} eq $shared_ip ) ? 'n' : 'y';
    }

    if ( exists $cpuser_hr->{'LOCALE'} ) {
        $cpuser_hr->{'LANG'} = delete $cpuser_hr->{'LOCALE'};
    }
    elsif ( exists $cpuser_hr->{'LANG'} ) {
        Cpanel::LoadModule::load_perl_module('Cpanel::Locale::Utils::Legacy');
        $cpuser_hr->{'LANG'} = Cpanel::Locale::Utils::Legacy::map_any_old_style_to_new_style( $cpuser_hr->{'LANG'} );
    }

    return $cpuser_hr;
}

1;
