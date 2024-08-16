package Cpanel::SecurityPolicy;

# cpanel - Cpanel/SecurityPolicy.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::PluginManager         ();
use Cpanel::SecurityPolicy::Utils ();

my $logger;
my $plugin_mgr;

sub _ensure_plugin_mgr {
    my ( $secdir, $user_secdir ) = @_;
    return if $plugin_mgr;
    $secdir      ||= Cpanel::SecurityPolicy::Utils::cpanel_libdir();
    $user_secdir ||= Cpanel::SecurityPolicy::Utils::user_libdir();
    $plugin_mgr  ||= Cpanel::PluginManager->new( directories => [ $secdir, $user_secdir ], namespace => Cpanel::SecurityPolicy::Utils::security_policy_ns() );
    return;
}

sub list_security_policies {
    _ensure_plugin_mgr(@_);

    return $plugin_mgr->list_plugin_names();
}

sub list_enabled_policies {
    my ( $conf, @secdirs ) = @_;
    _ensure_plugin_mgr(@secdirs);

    return {} unless defined $conf and 'HASH' eq ref $conf;
    return grep { exists $conf->{ 'SecurityPolicy::' . $_ } && $conf->{ 'SecurityPolicy::' . $_ } } $plugin_mgr->list_plugin_names();
}

# Only useful for testing.
sub _clear_plugins {
    $plugin_mgr = undef;
}

sub loadmodules {
    my %OPTS = @_;
    _ensure_plugin_mgr( @OPTS{ 'cpanel_libdir', 'user_libdir' } );

    if ( $OPTS{'all'} ) {
        $plugin_mgr->load_all_plugins();
    }
    else {
        my $conf = $OPTS{'conf'};
        foreach my $mod ( grep { exists $conf->{ 'SecurityPolicy::' . $_ } && $conf->{ 'SecurityPolicy::' . $_ } } $plugin_mgr->list_plugin_names() ) {
            $plugin_mgr->load_plugin_by_name($mod);
        }
    }

    my @loaded_secpolicy_modules = $plugin_mgr->get_loaded_plugins();
    if ( $OPTS{'verbose'} ) {
        require Cpanel::Logger;
        $logger ||= Cpanel::Logger->new();
        $logger->info( scalar(@loaded_secpolicy_modules) . ' security policies loaded' );
    }
    return \@loaded_secpolicy_modules;
}

sub reloadmodules {
    $plugin_mgr->reset_plugin_list();
    return loadmodules(@_);
}

#
# Returns 1 on the first policy violation.
# May also die on error condition, should be enclosed in an eval.
sub any_violations {
    my $secpol_list = shift;
    my ( $sec_ctxt, $cpconf_ref ) = @_;

    foreach my $module ( @{$secpol_list} ) {
        return 1 if $module->check_fails( $sec_ctxt, $cpconf_ref );
    }
    return;
}

sub get_violations {
    my ( $secpol_list, $sec_ctxt, $cpconf_ref ) = @_;

    my @violated;
    foreach my $module ( @{$secpol_list} ) {
        push @violated, $module if $module->check_fails( $sec_ctxt, $cpconf_ref );
    }

    return \@violated;
}

#
# Returns the most important violated policy or undef.
# May also die on error condition, should be enclosed in an eval.
sub get_first_violation {
    my $secpol_list = shift;
    my ( $sec_ctxt, $cpconf_ref ) = @_;

    foreach my $module ( @{$secpol_list} ) {
        return $module if $module->check_fails( $sec_ctxt, $cpconf_ref );
    }

    return;
}

#
# Return 1 if a violated security policy was processed
# May also die on error condition, should be enclosed in an eval.
sub process_violated_policy {
    my $policy = shift;
    my ( $form_ref, $sec_ctxt, $cpconf_ref, $logger ) = @_;

    $policy = $policy->[0] if 'ARRAY' eq ref $policy;    # handles list_violations or get_first_violation output.
    return unless defined $policy;

    my $ui = $policy->get_ui( $sec_ctxt->{'ui_style'} );
    die "securitypolicy: Missing security handling process for @{[$policy->name]} ($sec_ctxt->{'ui_style'}).\n"
      unless defined $ui;

    if ( exists $form_ref->{'secpolicy_ui'} and 'no' eq $form_ref->{'secpolicy_ui'} ) {
        print "HTTP/1.0 403 Forbidden\r\nContent-type: text/html\r\n\r\n", "<html><body><h1>Security Error</h1>\n<p>refresh page.</p></body></html>\n";

        # Handled, return empty hash as success.
        return {};
    }

    my $return = $ui->process( $form_ref, $sec_ctxt, $cpconf_ref );

    # The security policies we ship, return 'undef' or an empty hash on success
    if ( !defined $return || ( 'HASH' eq ref $return && scalar keys %{$return} == 0 ) ) {
        $logger->info("Security Policy Verified: ['@{[$policy->name]}'], User: ['$sec_ctxt->{'user'}'], Appname: ['$sec_ctxt->{'appname'}'], IP: ['$sec_ctxt->{'remoteip'}']");
    }
    else {
        $logger->info( "Security Policy Failed: ['@{[$policy->name]}'], User: ['$sec_ctxt->{'user'}'], Appname: ['$sec_ctxt->{'appname'}'], IP: ['$sec_ctxt->{'remoteip'}'], Error: ['" . ( $return->{'error'} || 'Unknown' ) . "']" );
    }
    return $return;
}

# Returns a count of the number of security policies with configuration functionality.
sub count_policy_config_entries {
    my ($secpol_list) = @_;
    return scalar grep { defined $_->get_config } @{$secpol_list};
}

#
# Perform the policy configuration step for all configurable policies.
# Returns a hash of arrays of descriptors for the config page keyed by policy
sub process_policy_configuration {
    my ( $secpol_list, $form_ref, $cpconf_ref, $is_save ) = @_;

    my %descs;
    foreach my $policy ( @{$secpol_list} ) {
        my $config = $policy->get_config();
        next unless defined $config;
        $descs{ $policy->{'name'} } = $config->config( $form_ref, $cpconf_ref, $is_save );
    }

    return %descs;
}

1;
