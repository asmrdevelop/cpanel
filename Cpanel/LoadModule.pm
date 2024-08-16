package Cpanel::LoadModule;

# cpanel - Cpanel/LoadModule.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

#The only allowed dependencies!
use Cpanel::Exception         ();
use Cpanel::LoadModule::Utils ();

my $logger;
my $has_perl_dir = 0;

sub _logger_warn {
    my ( $msg, $fail_ok ) = @_;

    # We don't care if we can't lazy-load a module during install.
    return if $fail_ok && $ENV{'CPANEL_BASE_INSTALL'} && index( $^X, '/usr/local/cpanel' ) == -1;

    if ( $INC{'Cpanel/Logger.pm'} ) {
        $logger ||= 'Cpanel::Logger'->new();
        $logger->warn($msg);
    }
    return warn $msg;
}

#For testing.
sub _reset_has_perl_dir {
    $has_perl_dir = 0;
    return;
}

#Use this for loading any Perl module. It die()s if module loading fails.
#NB: @LIST is as described in “perldoc -f use”, but for this function it
#can only take simple scalars.
sub load_perl_module {    ## no critic qw(Subroutines::RequireArgUnpacking)
    if ( -1 != index( $_[0], q<'> ) ) {
        die Cpanel::Exception::create_raw( 'InvalidParameter', "Module names with single-quotes are prohibited. ($_[0])" );
    }

    return $_[0] if Cpanel::LoadModule::Utils::module_is_loaded( $_[0] );

    my ( $mod, @LIST ) = @_;

    #We protect $@ and $! here because the eval()/use() below
    #will clobber them both. This can cause action-at-a-distance in
    #weird (but hard-to-debug) cases if the caller isn’t careful.
    #
    #It’s especially important to do that here because this code gets
    #called in DESTROY and exception handling logic.
    #
    local ( $!, $@ );

    if ( !is_valid_module_name($mod) ) {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a valid name for a Perl module.', [$mod] );
    }

    my $args_str;
    if (@LIST) {
        $args_str = join ',', map {
            die "Only scalar arguments allowed in LIST! (@LIST)" if ref;
            _single_quote($_);
        } @LIST;
    }
    else {
        $args_str = q<>;
    }

    #Use "use" rather than "require" because the latter will affect
    #the namespace table, even if the module fails to load.
    eval "use $mod ($args_str);";    ## no critic qw(BuiltinFunctions::ProhibitStringyEval)

    if ($@) {
        die Cpanel::Exception::create( 'ModuleLoadError', [ module => $mod, error => $@ ] );
    }

    #Perl won’t allow '0' as a package name, so we might as well
    #return something useful here.
    return $mod;
}

*module_is_loaded = *Cpanel::LoadModule::Utils::module_is_loaded;

*is_valid_module_name = *Cpanel::LoadModule::Utils::is_valid_module_name;

#----------------------------------------------------------------------
#NOTE: The functions below are ALL LEGACY and should NOT be used in new code.
#----------------------------------------------------------------------
#
#Error reporting is spotty and generally requires the caller to inquire as
#to whether the call succeeded to avoid the default of just ignoring failure,
#which, from this module, is almost certainly fatal in any context!
#
#The below functions also all publish their error status to $@, regardless
#of whether an error actually happens or not. You may want to "local $@"
#before calling them just as a precaution, though this shouldn't normally
#affect well-written code.
#
#----------------------------------------------------------------------

#This function prefixes the given module with "Cpanel::"
#and runs "Cpanel::$modpart"->${modpart}_init() if it exists.
sub loadmodule {
    return 1 if cpanel_namespace_module_is_loaded( $_[0] );

    return _modloader( $_[0] );
}

#XXX: If the module is already loaded, this will return empty. But this also
#returns empty if the module name is invalid. Basically, you can't trust this
#function's return to indicate whether the module is available for use,
#so you should probably use load_perl_module instead.
sub lazy_load_module {
    my $mod = shift;

    my $mod_path = $mod;
    $mod_path =~ s{::}{/}g;
    if ( exists $INC{ $mod_path . '.pm' } ) {
        return;
    }

    if ( !is_valid_module_name($mod) ) {
        _logger_warn("Cpanel::LoadModule: Invalid module name ($mod)");
        return;
    }

    #Use "use" rather than "require" because the latter will affect
    #the namespace table, even if the module fails to load.
    eval "use $mod ();";

    if ($@) {
        delete $INC{ $mod_path . '.pm' };
        _logger_warn( "Cpanel::LoadModule:: Failed to load module $mod - $@", 1 );
        return;
    }

    return 1;
}

#----------------------------------------------------------------------

#This prefixes "Cpanel::" onto the given module name.
sub cpanel_namespace_module_is_loaded {
    ## temporary variable; otherwise getting "Modification of a read-only value attempted"
    ##   when substituting on $_[0]
    my ($modpart) = @_;
    $modpart =~ s{::}{/}g;
    return exists $INC{"Cpanel/$modpart.pm"} ? 1 : 0;
}

sub _modloader {
    my $module = shift;
    if ( !$module ) {
        _logger_warn("Empty module name passed to modloader");
        return;
    }
    if ( !is_valid_module_name($module) ) {
        _logger_warn("Invalid module name ($module) passed to modloader");
        return;
    }

    #Use "use" rather than "require" because the latter will affect
    #the namespace table, even if the module fails to load.
    eval qq[ use Cpanel::${module}; Cpanel::${module}::${module}_init() if "Cpanel::${module}"->can("${module}_init"); ];    # PPI USE OK - This looks like usage of the Cpanel module and it's not.

    if ($@) {
        _logger_warn("Error loading module $module - $@");
        return;
    }

    return 1;
}

# SYNTAX is a hack to avoid
# perl compiling this incorrectly
sub _single_quote {
    local ($_) = $_[0];
    s/([\\'])/\\$1/g;
    return qq('$_');
}

1;
