package Cpanel::Server::Type::Change::Backend;

# cpanel - Cpanel/Server/Type/Change/Backend.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Server::Type::Change::Backend - helper logic for
L<Cpanel::Server::Type::Change>

=cut

#----------------------------------------------------------------------

use Cpanel::Imports;

use Cpanel::ConfigFiles ();
use Cpanel::Debug       ();
use Cpanel::LoadModule  ();
use Cpanel::ServerTasks ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 sync_service_subdomains( \@DISABLED_ROLES, \@ENABLED_ROLES )

This iterates through the given role module arrays (whose members are,
e.g., C<Cpanel::Server::Type::Role::WebDisk::Change>). It assembles a
list of service subdomains to enable and/or disable, logs about that
(i.e., C<Cpanel::Debug::log_info()>), then enqueues a background task
to do the work.

=cut

sub sync_service_subdomains {
    my ( $disabled_roles_ar, $enabled_roles_ar ) = @_;

    my @tasks;

    if ( my @subdomains = get_role_service_subs(@$disabled_roles_ar) ) {
        Cpanel::Debug::log_info( locale()->maketext( 'Deleting users’ [list_and_quoted,_1] service subdomains …', \@subdomains ) );
        push @tasks, "remove_specific_service_subdomains @subdomains";
    }

    if ( my @subdomains = get_role_service_subs(@$enabled_roles_ar) ) {
        Cpanel::Debug::log_info( locale()->maketext( 'Creating users’ [list_and_quoted,_1] service subdomains …', \@subdomains ) );
        push @tasks, "add_specific_service_subdomains @subdomains";
    }

    if (@tasks) {
        Cpanel::ServerTasks::queue_task( ['ProxySubdomains'], @tasks );
    }

    return;
}

#----------------------------------------------------------------------

=head2 get_role_service_subs(@role_modules)

This iterates through the given role module arrays and generates a list of
service subdomains that should be enabled when the given roles are enabled.

=cut

sub get_role_service_subs {

    my (@role_modules) = @_;

    my @subdomains;

    for my $module (@role_modules) {
        $module =~ s<::Change\z><>;

        Cpanel::LoadModule::load_perl_module($module);

        push @subdomains, @{ $module->SERVICE_SUBDOMAINS() };
    }

    return @subdomains;
}

#----------------------------------------------------------------------

=head2 sync_rpms( @CHANGE_MODULE_NAMESPACES )

Pass in a list of role-change module namespaces
(e.g., C<Cpanel::Server::Type::Role::FTP>), and each of those modules’
C<RPM_TARGETS()> methods will be called to create a list of RPM targets
that will be synchronized via F<scripts/check_cpanel_pkgs>.

All errors trigger warnings; nothing is returned.

=cut

sub sync_rpms (@change_nss) {
    my @non_change_nss = map { _get_non_change_ns($_) } @change_nss;

    my @targets = map { @{ $_->RPM_TARGETS() } } @non_change_nss;

    if (@targets) {
        require Cpanel::ArrayFunc::Uniq;
        @targets = Cpanel::ArrayFunc::Uniq::uniq(@targets);

        Cpanel::Debug::log_info( locale()->maketext('Synchronizing installed packages …') );

        my $bin_path = "$Cpanel::ConfigFiles::CPANEL_ROOT/scripts/check_cpanel_pkgs";

        require Cpanel::SafeRun::Object;

        local $@;

        my $ok = eval {
            my $run = Cpanel::SafeRun::Object->new(
                program => $bin_path,
                args    => [ '--fix', '--long-list', '--targets', @targets ],
                stdout  => \*STDOUT,
                stderr  => \*STDERR,
            );

            warn $run->autopsy() if $run->CHILD_ERROR();

            1;
        };

        warn "exec $bin_path: $@" if !$ok;
    }

    return;
}

# Convert a ::Change namespace to a “regular” (i.e., non-Change) one:
sub _get_non_change_ns ($ns) {
    $ns =~ s<::Change\z><> or die "Unexpected “change” namespace: $ns";
    return $ns;
}

1;
