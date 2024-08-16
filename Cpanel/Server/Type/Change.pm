package Cpanel::Server::Type::Change;

# cpanel - Cpanel/Server/Type/Change.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::Server::Type::Change - Provides methods for changing the server type

=head1 SYNOPSIS

    use Cpanel::Server::Type::Change;

    Cpanel::Server::Type::Change::activate_profile( $new_profile, $options );
    my $current_profile = Cpanel::Server::Type::Change::get_current_profile();

=head1 SUBROUTINES

=cut

use strict;
use warnings;

use Cpanel::Autodie                           ();
use Cpanel::Debug                             ();
use Cpanel::DynamicUI::App                    ();
use Cpanel::LoadModule                        ();
use Cpanel::PIDFile                           ();
use Cpanel::Server::Type                      ();
use Cpanel::Server::Type::Change::Backend     ();
use Cpanel::Server::Type::Profile             ();
use Cpanel::Server::Type::Profile::Constants  ();
use Cpanel::Server::Type::Role::TouchFileRole ();
use Cpanel::Set                               ();

use Cpanel::Imports;

my $_PIDFILE_PATH = '/var/cpanel/server_profile_switch_pid';

# for testing
our $_LAST_PID;
our $_PROFILE_LOG_CLASS;

BEGIN {
    $_PROFILE_LOG_CLASS = 'Cpanel::Server::Type::Log';
}

=head2 start_profile_activation

Spawns a daemonized process that activates a server profile.

=over

=item INPUT

This function’s inputs are identical to the C<activate_profile> function.

=item OUTPUT

=over

On success, this function returns the id of the profile activation log.

=back

=back

=cut

sub start_profile_activation {

    my ( $code, $optional, $force ) = @_;

    my $product_type = Cpanel::Server::Type::get_producttype();

    if ( $product_type ne Cpanel::Server::Type::Profile::Constants::STANDARD && $code ne $product_type ) {
        die locale()->maketext( "Invalid server profile specified: “[_1]”.", $code );
    }

    # Use this to have the child tell the parent the log ID.
    pipe( my $pr, my $cw ) or die "pipe(): $!";

    require Cpanel::Daemonizer::Tiny;

    $_LAST_PID = Cpanel::Daemonizer::Tiny::run_as_daemon_with_options(
        {
            excludes => [$cw],
        },
        sub {
            require Cpanel::Locale::Context;
            local $Cpanel::Locale::Context::DEFAULT_OUTPUT_CONTEXT = 'plain';

            require Whostmgr::UI;
            local $Whostmgr::UI::nohtml = 1;

            # Without this, CLI invocations of this API call will log to
            # $ULC/logs/error_log rather than to the profile activation’s
            # log file.
            require Cpanel::Logger;
            local $Cpanel::Logger::ALWAYS_OUTPUT_TO_STDERR = 1;

            Cpanel::LoadModule::load_perl_module($_PROFILE_LOG_CLASS);

            my $log_id = $_PROFILE_LOG_CLASS->create_new( SUCCESS => 0 );

            syswrite( $cw, $log_id ) or die "send log ID to parent: $!";
            close $cw;

            $_PROFILE_LOG_CLASS->redirect_stdout_and_stderr($log_id);

            activate_profile( $code, $optional, $force );

            $_PROFILE_LOG_CLASS->set_metadata( $log_id, SUCCESS => 1 );
        }
    );

    close $cw;

    sysread( $pr, my $log_id, 512 ) or do {
        die "Failed to read log ID from background process: $!";
    };
    close $pr;

    return $log_id;
}

=head2 activate_profile

Activates the server profile, enabling or disabling specific roles for the server

=over 2

=item Input

=over 3

=item C<SCALAR>

A unique identifier corresponding to the new server profile

=item C<HASHREF>

A HASHREF of optional modules to disable or enable when changing the server roles for the new type

=back

=item Output

=over 3

None

=back

=back

=cut

sub activate_profile {

    my ( $new_profile, $options, $force ) = @_;

    $options ||= {};

    my $META = Cpanel::Server::Type::Profile::get_meta_with_descriptions();

    if ( !defined $META->{$new_profile} ) {
        die locale()->maketext( "Invalid server profile specified: “[_1]”.", $new_profile );
    }

    Cpanel::PIDFile->do(
        $_PIDFILE_PATH,
        sub {

            # It’s best to read the current profile under the mutex so that
            # we’re sure the profile doesn’t change out from under us.
            my $current_profile = Cpanel::Server::Type::Profile::get_current_profile();

            if ( !$force && $new_profile eq $current_profile && !scalar keys %$options ) {
                Cpanel::Debug::log_info( locale()->maketext( "The server profile is already set to “[_1]”.", $META->{$new_profile}{name}->to_string() ) );
                return;
            }

            _setup_directory($Cpanel::Server::Type::Role::TouchFileRole::ROLES_TOUCHFILE_BASE_PATH);

            Cpanel::Debug::log_info( locale()->maketext( "Switching to the “[_1]” server profile …", $META->{$new_profile}{name}->to_string() ) );

            # Pull all of the services from all of the roles
            my ( $all_services, $services_by_role, $restart_services_by_role ) = _get_services($META);

            # Determine the changes that need to be made
            my ( $role_enabler_modules, $role_disabler_modules, $needed_services ) = _get_enabled_and_disabled_roles( $new_profile, $META->{$new_profile}, $options, $services_by_role );

            my ( @changed_roles, @changed_services );

            _disable_profile_services_and_roles(
                role_changers    => $role_disabler_modules,
                all_services     => $all_services,
                needed_services  => $needed_services,
                changed_roles    => \@changed_roles,
                changed_services => \@changed_services,
                force            => $force,
            );

            my @disabled_roles = @changed_roles;

            _enable_profile_services_and_roles(
                role_changers    => $role_enabler_modules,
                needed_services  => $needed_services,
                changed_roles    => \@changed_roles,
                changed_services => \@changed_services,
                force            => $force,
            );

            Cpanel::Server::Type::Change::Backend::sync_rpms(@changed_roles);

            my @enabled_roles = Cpanel::Set::difference(
                \@changed_roles,
                \@disabled_roles,
            );

            Cpanel::Server::Type::Change::Backend::sync_service_subdomains( \@disabled_roles, \@enabled_roles );

            # Some services may need to be restarted because their context changes by enabling or disabling a role
            _restart_services( \@changed_roles, $restart_services_by_role, \@changed_services );

            if ( Cpanel::Autodie::exists($Cpanel::DynamicUI::App::DYNAMICUI_TOUCHFILE_DIR) ) {
                my $now = time();
                utime( $now, $now, $Cpanel::DynamicUI::App::DYNAMICUI_TOUCHFILE_DIR ) or do {
                    warn "utime($Cpanel::DynamicUI::App::DYNAMICUI_TOUCHFILE_DIR): $!";
                };
            }
            else {
                _setup_directory( $Cpanel::DynamicUI::App::DYNAMICUI_TOUCHFILE_DIR, 0755 );
            }

            require Whostmgr::Templates::Command::Directory;
            Whostmgr::Templates::Command::Directory::clear_cache_dir();

            Cpanel::Server::Type::Profile::_reset_cache();

            Cpanel::Debug::log_info( locale()->maketext( "The system is set to the “[_1]” profile.", $META->{$new_profile}{name}->to_string() ) );
        }
    );

    return;
}

sub _enable_profile_services_and_roles {

    my %opts = @_;

    # The roles may install or add things when enabling that the services need, so enable the roles first
    for my $changer ( @{ $opts{role_changers} } ) {
        my $role_module = $changer;
        $role_module =~ s<::Change\z><> or do {
            die "Malformed disabler module name “$role_module”!";
        };

        next if !$opts{force} && Cpanel::LoadModule::load_perl_module($role_module)->is_enabled();

        Cpanel::LoadModule::load_perl_module($changer);

        if ( $changer->new()->enable() ) {
            push @{ $opts{changed_roles} }, $changer;
        }
    }

    # Make sure the services are installed, we do this after enabling the roles because roles can install new components
    require Cpanel::Services::Installed;
    my @enable_services = grep { Cpanel::Services::Installed::service_is_installed($_) } keys %{ $opts{needed_services} };

    if (@enable_services) {

        # We pass all of the enabled services to Whostmgr::Services in case there's any cruft leftover (disable touchfiles, etc…)
        # But we want to check which are already enabled here in case we need to restart them later
        require Cpanel::Services::Enabled;
        push @{ $opts{changed_services} }, grep { !Cpanel::Services::Enabled::is_provided($_) } @enable_services;

        require Whostmgr::Services;
        Cpanel::Debug::log_info( locale()->maketext( "Verifying that the following [numerate,_1,service,services] are enabled: [list_and_quoted,_2] …", scalar @enable_services, [ sort @enable_services ] ) );
        Whostmgr::Services::enable_and_monitor(@enable_services);
    }

    return;
}

sub _disable_profile_services_and_roles {

    my %opts = @_;

    # The roles may uninstall or remove things when disabling that the services need, so first disable any service that's not needed and running
    require Cpanel::Services::Enabled;
    my @disable_services = grep { !exists $opts{needed_services}->{$_} && Cpanel::Services::Enabled::is_enabled($_) } keys %{ $opts{all_services} };

    if (@disable_services) {
        require Whostmgr::Services;
        Cpanel::Debug::log_info( locale()->maketext( "Disabling [numerate,_1,service,services]: [list_and_quoted,_2] …", scalar @disable_services, [ sort @disable_services ] ) );
        Whostmgr::Services::disable(@disable_services);
        push @{ $opts{changed_services} }, @disable_services;
    }

    for my $changer ( @{ $opts{role_changers} } ) {
        my $role_module = $changer;
        $role_module =~ s<::Change\z><> or do {
            die "Malformed disabler module name “$role_module”!";
        };

        next if !$opts{force} && !Cpanel::LoadModule::load_perl_module($role_module)->is_enabled();

        Cpanel::LoadModule::load_perl_module($changer);

        if ( $changer->new()->disable() ) {
            push @{ $opts{changed_roles} }, $changer;
        }
    }

    return;
}

sub _get_services {

    my ($META) = @_;

    my ( %all_services, %services_by_role, %restart_services_by_role );

    foreach my $profile ( keys %$META ) {

        my @roles;

        foreach my $role (qw(enabled_roles optional_roles)) {
            push @roles, @{ $META->{$profile}{$role} } if defined $META->{$profile}{$role};
        }

        my $disabled_roles_ar = Cpanel::Server::Type::Profile::get_disabled_roles_for_profile($profile);
        push @roles, @$disabled_roles_ar if $disabled_roles_ar;

        foreach my $role (@roles) {

            next if exists $services_by_role{$role};

            Cpanel::LoadModule::load_perl_module($role);
            next if !$role->new()->is_available();

            $services_by_role{$role}                = $role->SERVICES();
            @all_services{ @{ $role->SERVICES() } } = ();
            $restart_services_by_role{$role}        = $role->RESTART_SERVICES();
        }

    }

    return ( \%all_services, \%services_by_role, \%restart_services_by_role );
}

sub _get_enabled_and_disabled_roles {
    my ( $profile_code, $profile, $options, $services_by_role ) = @_;

    my ( @enabled_roles, @disabled_roles, %needed_services );

    if ( $profile->{enabled_roles} ) {
        foreach my $role ( @{ $profile->{enabled_roles} } ) {
            Cpanel::LoadModule::load_perl_module($role);
            next if !$role->new()->is_available();
            push @enabled_roles, "${role}::Change";
            @needed_services{ @{ $services_by_role->{$role} } } = ();
        }
    }

    my $disabled_roles_ar = Cpanel::Server::Type::Profile::get_disabled_roles_for_profile($profile_code);
    if ($disabled_roles_ar) {
        foreach my $role ( @{$disabled_roles_ar} ) {
            Cpanel::LoadModule::load_perl_module($role);
            next if !$role->new()->is_available();
            push @disabled_roles, "${role}::Change";
        }
    }

    if ( $profile->{optional_roles} ) {

        foreach my $role ( @{ $profile->{optional_roles} } ) {

            Cpanel::LoadModule::load_perl_module($role);
            next if !$role->new()->is_available();

            my $change = "${role}::Change";

            if ( $options->{$role} ) {
                push @enabled_roles, $change;
                @needed_services{ @{ $services_by_role->{$role} } } = ();
            }
            else {
                push @disabled_roles, $change;
            }

        }

    }

    return ( \@enabled_roles, \@disabled_roles, \%needed_services );
}

sub _restart_services {

    my ( $changed_roles, $restart_services_by_role, $changed_services ) = @_;

    my %restart_services;

    if (@$changed_roles) {

        require Whostmgr::Services;
        require Cpanel::Services::Installed;

        for (@$changed_roles) {

            my $role = $_;
            substr( $role, index( $role, '::Change' ), 8 ) = "";

            foreach my $service ( @{ $restart_services_by_role->{$role} } ) {

                # Services might have been installed or uninstalled via the role changes, so check their install status before restarting them
                next if !Cpanel::Services::Installed::service_is_installed($service);

                # If we enabled or disabled a service, we don't need to restart it. We also only need to restart it if it's running
                if ( !( grep { $_ eq $service } @$changed_services ) && Whostmgr::Services::is_running($service) ) {
                    $restart_services{$service} = undef;
                }
            }

        }

    }

    $restart_services{'cpsrvd'} = ();

    Cpanel::Debug::log_info( locale()->maketext( "Restarting [numerate,_1,service,services]: [list_and_quoted,_2] …", scalar keys %restart_services, [ sort keys %restart_services ] ) );

    require Cpanel::Services::Restart;
    for ( sort keys %restart_services ) {
        Cpanel::Services::Restart::restartservice( $_, 1 );
    }

    return;
}

sub _setup_directory {

    my ( $path, $base_path_perms ) = @_;

    $base_path_perms ||= 0751;

    Cpanel::Autodie::exists($path);

    if ( -d _ ) {
        Cpanel::Autodie::chmod( $base_path_perms, $path );
    }
    else {
        Cpanel::Autodie::mkdir( $path, $base_path_perms );
    }

    return;
}

1;
