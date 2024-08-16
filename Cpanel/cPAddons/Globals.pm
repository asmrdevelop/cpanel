package Cpanel::cPAddons::Globals;

# cpanel - Cpanel/cPAddons/Globals.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Imports;
use Cpanel::Config::LoadCpConf  ();
use Cpanel::cPAddons::Cache     ();
use Cpanel::cPAddons::Class     ();
use Cpanel::cPAddons::Integrity ();
use Cpanel::cPAddons::Util      ();

# This is terrible, but the purpose of this module is to enable a transition
# to something less terrible without requiring the interim step of having
# the new cPAddons-related modules reach back into the original set of globals
# in Cpanel::cPAddons.

=head1 NAME

Cpanel::cPAddons::Globals

=head1 DESCRIPTION

This module encapsulates the remaining globals that were originally in Cpanel::cPAddons.

=cut

our %disallowed_feat;
our $_self = '';
our $mod   = '';
our $force = '';

our $allow_html = 0;
our $locale;    # for object later
our $default_vendor = 'cPanel';
our $cpconf_ref;
our $moderation_request_notify  = 0;
our $max_moderation_req_all_mod = 99;
our $max_moderation_req_per_mod = 99;
our $admincontactemail          = 'root';
our %cpanelincluded;
our $pal               = 'cPanel';
our $is_default_vendor = 0;
our $vendor_urls       = [];
our %approved_vendors;
our $user;
our $homedir;

our $force_text = 'I fully understand what I am doing and take full responsibility for my actions. I have backed up all my data so I can remove the installation, reinstall fresh and import my old info into the new install if necessary. I understand that anything that breaks by forcing this upgrade is 100% my responsibility.';

our $suppress_init_errors = 0;    # For testing

##
## Initialization functions
##

=head1 FUNCTIONS

=head2 init_globals()

This function initializes the globals in the Cpanel::cPAddons::Globals module. This must be done before using the
cPAddons system, as other modules rely on these variables.

=head3 Arguments

none

=head3 Returns

True on success / False on failure

=cut

my $_did_init_globals = 0;

sub init_globals {    ## no critic qw(Subroutines::ProhibitExcessComplexity)
    return if $_did_init_globals;

    require Cpanel;

    $_did_init_globals = 1;

    $Cpanel::NEEDSREMOTEPASS{'cPAddons'} = 1;
    $locale = locale();

    for my $path ( '/var/cpanel/cpaddons_moderated', '/var/cpanel/cpaddons_disabled' ) {
        Cpanel::cPAddons::Cache::read_cache( $path, {} ) if -e $path && !-e "$path.yaml";
    }

    $Cpanel::cPAddons::Class::SINGLETON = Cpanel::cPAddons::Class->new();
    %disallowed_feat                    = $Cpanel::cPAddons::Class::SINGLETON->get_disabled_addons();
    %approved_vendors                   = $Cpanel::cPAddons::Class::SINGLETON->get_approved_vendors();

    $_self = $ENV{'SCRIPT_NAME'}       || '';
    $mod   = $main::formref->{'addon'} || $Cpanel::FORM{'addon'};

    $user    = $ENV{'CPASUSER'} || $Cpanel::user;
    $homedir = ( getpwnam $user )[7];

    # TODO: Remove or provide an interface/UI for managing this
    if ( -e "$homedir/.cpaddons_defaultvendor" ) {

        my $tmp;
        if ( open my $dv, '<', "$homedir/.cpaddons_defaultvendor" ) {
            chomp( $tmp = <$dv> );
            close $dv;
        }
        $default_vendor = $tmp if $tmp;
    }

    $cpconf_ref = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();

    local @INC = ( '/usr/local/cpanel/cpaddons', @INC );
    $admincontactemail = Cpanel::cPAddons::Util::admin_contact_email($cpconf_ref);

    my $need_admin_to_make_conf = 0;
    if ( -e '/usr/local/cpanel/cpaddons/cPAddonsConf.pm' ) {
        require cPAddonsConf;
        if ( !$@ ) {
            for ( keys %cPAddonsConf::vend ) {
                $approved_vendors{$_} = $cPAddonsConf::vend{$_};
            }
        }
    }
    else {
        $need_admin_to_make_conf++;
    }

    # TODO: To complex a single statement, break down better (see: LC-6735)
    $pal =
        ( defined $main::formref->{'changevendor'} && exists $approved_vendors{ $main::formref->{'changevendor'} } ) ? $main::formref->{'changevendor'}
      : exists $approved_vendors{$default_vendor}                                                                    ? $default_vendor
      :                                                                                                                'cPanel';

    if ($mod) {

        # Set the pal only if its approved
        my ($vendor_from_module_name) = split /\:\:/, $mod;
        $pal = $vendor_from_module_name
          if defined $vendor_from_module_name
          && exists $approved_vendors{$vendor_from_module_name};

        # TODO: Shouldn't this do something if its not approved.
    }

    # Verify we can load the MD5 file for legacy addons
    if ( -e "/usr/local/cpanel/cpaddons/cPAddonsMD5/$pal.pm" ) {
        eval "use cPAddonsMD5::$pal;";    ## no critic qw(BuiltinFunctions::ProhibitStringyEval)
        if ( $@ && !$suppress_init_errors ) {
            logger()->warn( 'Error loading cPAddonsMD5::' . $pal . ': ' . $@ );
            _notices()->add_critical_error( locale()->maketext( 'The system could not load the MD5 file for the [_1] [asis,cPAddons] via module [_2]: [_3]', $pal, 'cPAddonsMD5::' . $pal, $@ ) );
            return;
        }
    }
    else {
        $need_admin_to_make_conf++;
    }

    my ( $ok, $cpanelincluded_hr ) = Cpanel::cPAddons::Integrity::get_cpanel_included();
    $need_admin_to_make_conf++ if !$ok;

    %cpanelincluded = %$cpanelincluded_hr;

    if ( $need_admin_to_make_conf && !$suppress_init_errors ) {
        _notices()->add_error( locale()->maketext('No Site Software configuration found. Contact your hosting provider and ask that they configure Site Software.') );
        $ENV{'cpaddons_init_failed'} = 1;    ## no critic qw(Variables::RequireLocalizedPunctuationVars) -- legacy
    }
    else {
        $ENV{'cpaddons_init_failed'} = 0;    ## no critic qw(Variables::RequireLocalizedPunctuationVars) -- legacy
    }

    use strict 'refs';

    # TODO: Need to do something with this in the templates. LC-6736
    for my $vendor_name ( sort keys %approved_vendors ) {
        push @$vendor_urls, "$_self?changevendor=$vendor_name" if $vendor_name ne $pal;
        $is_default_vendor = $vendor_name eq $default_vendor;
    }

    return 1;
}

our $notices;

sub _notices {
    return $notices if $notices;

    # Only loads Notices when we need to post one
    require Cpanel::cPAddons::Notices;
    return ( $notices ||= Cpanel::cPAddons::Notices::singleton() );
}

1;
