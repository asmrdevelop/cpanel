package Cpanel::TaskProcessors::ProxySubdomains;

# cpanel - Cpanel/TaskProcessors/ProxySubdomains.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

{

    package Cpanel::TaskProcessors::RemoveAutoDiscoverProxySubdomains;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub overrides {
        my ( $self, $new, $old ) = @_;
        my $is_dupe = $self->is_dupe( $new, $old );
        return $is_dupe;
    }

    sub is_valid_args {
        my ( $self, $task ) = @_;
        my $numargs  = scalar $task->args();
        my $is_valid = ( $numargs <= 1 );
        return $is_valid;
    }

    sub _do_child_task {
        my ( $self, $task, $logger ) = @_;
        my ($old_autodiscovery_host) = $task->args();

        $self->checked_system(
            {
                'logger' => $logger,
                'name'   => 'scripts/proxydomains/autodiscover/remove',
                'cmd'    => '/usr/local/cpanel/scripts/proxydomains',
                'args'   => [ '--subdomain=autoconfig,autodiscover', '--force_autodiscover_support=1', ( $old_autodiscovery_host ? ( '--old_autodiscover_host=' . $old_autodiscovery_host ) : () ), 'remove' ],
            }
        );
        return;
    }

    sub deferral_tags {
        return qw/httpd/;
    }
}

{

    package Cpanel::TaskProcessors::AddAutoDiscoverProxySubdomains;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub overrides {
        my ( $self, $new, $old ) = @_;
        my $is_dupe = $self->is_dupe( $new, $old );
        return $is_dupe;
    }

    sub is_valid_args {
        my ( $self, $task ) = @_;
        my $numargs  = scalar $task->args();
        my $is_valid = ( $numargs <= 1 );
        return $is_valid;
    }

    sub _do_child_task {
        my ( $self, $task, $logger ) = @_;
        my ($old_autodiscovery_host) = $task->args();

        $self->checked_system(
            {
                'logger' => $logger,
                'name'   => 'scripts/proxydomains/autodiscover/add',
                'cmd'    => '/usr/local/cpanel/scripts/proxydomains',
                'args'   => [ '--subdomain=autoconfig,autodiscover', '--force_autodiscover_support=1', ( $old_autodiscovery_host ? ( '--old_autodiscover_host=' . $old_autodiscovery_host ) : () ), 'add' ],
            }
        );

        return;
    }

    sub deferral_tags {
        return qw/httpd/;
    }
}

{

    package Cpanel::TaskProcessors::UpdateAutoDiscoverProxySubdomains;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub overrides {
        my ( $self, $new, $old ) = @_;
        my $is_dupe = $self->is_dupe( $new, $old );
        return $is_dupe;
    }

    sub is_valid_args {
        my ( $self, $task ) = @_;
        my $numargs  = scalar $task->args();
        my $is_valid = ( $numargs <= 1 );
        return $is_valid;
    }

    sub _do_child_task {
        my ( $self, $task, $logger ) = @_;
        my ($old_autodiscovery_host) = $task->args();

        $self->checked_system(
            {
                'logger' => $logger,
                'name'   => 'scripts/proxydomains/autodiscover/update',
                'cmd'    => '/usr/local/cpanel/scripts/proxydomains',
                'args'   => [ '--subdomain=autoconfig,autodiscover', '--force_autodiscover_support=1', ( $old_autodiscovery_host ? ( '--old_autodiscover_host=' . $old_autodiscovery_host ) : () ), '--no_replace=0', 'add' ],
            }
        );

        return;
    }

    sub deferral_tags {
        return qw/httpd/;
    }
}

{

    package Cpanel::TaskProcessors::RemoveProxySubdomains;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub overrides {
        my ( $self, $new, $old ) = @_;
        my $is_dupe = $self->is_dupe( $new, $old );
        return $is_dupe;
    }

    sub is_valid_args {
        my ( $self, $task ) = @_;
        my $numargs  = scalar $task->args();
        my $is_valid = ( $numargs <= 1 );
        return $is_valid;
    }

    sub _do_child_task {
        my ( $self, $task, $logger ) = @_;
        my ($old_autodiscovery_host) = $task->args();

        $self->checked_system(
            {
                'logger' => $logger,
                'name'   => 'scripts/proxydomains/remove',
                'cmd'    => '/usr/local/cpanel/scripts/proxydomains',
                'args'   => [ '--force_autodiscover_support=1', ( $old_autodiscovery_host ? ( '--old_autodiscover_host=' . $old_autodiscovery_host ) : () ), 'remove' ],
            }
        );

        return;
    }

    sub deferral_tags {
        return qw/httpd/;
    }
}

{

    package Cpanel::TaskProcessors::AddProxySubdomains;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub overrides {
        my ( $self, $new, $old ) = @_;
        my $is_dupe = $self->is_dupe( $new, $old );
        return $is_dupe;
    }

    sub is_valid_args {
        my ( $self, $task ) = @_;
        my $numargs  = scalar $task->args();
        my $is_valid = ( $numargs <= 1 );
        return $is_valid;
    }

    sub _do_child_task {
        my ( $self, $task, $logger ) = @_;
        my ($old_autodiscovery_host) = $task->args();

        $self->checked_system(
            {
                'logger' => $logger,
                'name'   => 'scripts/proxydomains/add',
                'cmd'    => '/usr/local/cpanel/scripts/proxydomains',
                'args'   => [ ( $old_autodiscovery_host ? ( '--old_autodiscover_host=' . $old_autodiscovery_host ) : () ), 'add' ],
            }
        );

        return;
    }

    sub deferral_tags {
        return qw/httpd/;
    }
}

{

    package Cpanel::TaskProcessors::AlterSpecificServiceSubdomains;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    use constant is_dupe   => 0;
    use constant overrides => 0;

    use constant deferral_tags => qw/httpd/;

    sub is_valid_args {
        my ( $self, $task ) = @_;

        my @args = $task->args();

        my $is_valid = ( @args >= 1 );

        $is_valid &&= do {
            require Cpanel::Proxy::Tiny;
            my $all_hr = Cpanel::Proxy::Tiny::get_known_proxy_subdomains( { include_disabled => 1 } );

            my @good = grep { exists $all_hr->{$_} } @args;

            @good == @args;
        };

        return $is_valid;
    }

    sub _do_child_task {
        my ( $self, $task, $logger ) = @_;

        $self->checked_system(
            {
                'logger' => $logger,
                'name'   => "scripts/proxydomains/" . $self->_SCRIPT_ACTION(),
                'cmd'    => '/usr/local/cpanel/scripts/proxydomains',
                'args'   => [
                    '--allow_disabled',
                    "--subdomain=" . join( ',', $task->args() ),
                    $self->_SCRIPT_ACTION(),
                ],
            }
        );

        return;
    }
}

{

    package Cpanel::TaskProcessors::AddSpecificServiceSubdomains;

    use parent -norequire => 'Cpanel::TaskProcessors::AlterSpecificServiceSubdomains';

    use constant _SCRIPT_ACTION => 'add';
}

{

    package Cpanel::TaskProcessors::RemoveSpecificServiceSubdomains;

    use parent -norequire => 'Cpanel::TaskProcessors::AlterSpecificServiceSubdomains';

    use constant _SCRIPT_ACTION => 'remove';
}

sub to_register {
    return (
        [ 'add_specific_service_subdomains',      Cpanel::TaskProcessors::AddSpecificServiceSubdomains->new() ],
        [ 'remove_specific_service_subdomains',   Cpanel::TaskProcessors::RemoveSpecificServiceSubdomains->new() ],
        [ 'remove_autodiscover_proxy_subdomains', Cpanel::TaskProcessors::RemoveAutoDiscoverProxySubdomains->new() ],
        [ 'add_autodiscover_proxy_subdomains',    Cpanel::TaskProcessors::AddAutoDiscoverProxySubdomains->new() ],
        [ 'update_autodiscover_proxy_subdomains', Cpanel::TaskProcessors::UpdateAutoDiscoverProxySubdomains->new() ],
        [ 'remove_proxy_subdomains',              Cpanel::TaskProcessors::RemoveProxySubdomains->new() ],
        [ 'add_proxy_subdomains',                 Cpanel::TaskProcessors::AddProxySubdomains->new() ]
    );

}

1;
