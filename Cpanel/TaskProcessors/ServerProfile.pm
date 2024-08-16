package Cpanel::TaskProcessors::ServerProfile;

# cpanel - Cpanel/TaskProcessors/ServerProfile.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::TaskProcessors::ServerProfile - Task processor for changing the server profile based on the license

=head1 SYNOPSIS

    use Cpanel::TaskProcessors::ServerProfile;

=head1 DESCRIPTION

    Launches a forced profile activation based on the product type in the license file.

=head1 INTERFACE

    This module defines a subclass of L<Cpanel::TaskQueue::FastSpawn> and a package method.

=head2 Cpanel::TaskProcessors::ServerProfile::to_register

    Used by the L<Cpanel::TaskQueue::PluginManager> to register the included classes.

=head2 Cpanel::TaskProcessors::ServerProfile::ProfileChanged

    Gets the product type from the license and forces a profile activation with that type

=cut

{

    package Cpanel::TaskProcessors::ServerProfile::ProfileChanged;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub _do_child_task {
        my ( $self, $task, $logger ) = @_;
        $logger->info("Updating roles after server type change.");
        require Cpanel::Server::Type;
        require Cpanel::Server::Type::Change;
        require Cpanel::Server::Type::Profile::Constants;
        require Cpanel::Server::Type::Profile::Roles;

        my $product_type = Cpanel::Server::Type::get_producttype();

        if ( $product_type ne Cpanel::Server::Type::Profile::Constants::STANDARD() && $product_type ne Cpanel::Server::Type::Profile::Constants::DNSONLY() ) {

            local $@;
            my $optional_roles = eval { Cpanel::Server::Type::Profile::Roles::get_optional_roles_for_profile($product_type) };

            if ($@) {
                $logger->error( $@->isa('Cpanel::Exception') ? $@->get_string() : $@ );
            }
            else {
                my $log_id = Cpanel::Server::Type::Change::start_profile_activation( $product_type, $optional_roles, 1 );
                $logger->info("Queued server profile activation (log id: $log_id).");
            }

        }
        else {
            $logger->info("Product type is $product_type, skipping profile activation.");
        }

        return;
    }

}

sub to_register {
    return (
        [ 'force_profile_activation', Cpanel::TaskProcessors::ServerProfile::ProfileChanged->new() ],
    );
}

1;
