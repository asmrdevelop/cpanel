package Cpanel::TaskProcessors::CpServicesTasks;

# cpanel - Cpanel/TaskProcessors/CpServicesTasks.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::LoadModule ();

{

    package Cpanel::TaskProcessors::CpServicesTasks::StartCpsrvd;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub overrides {
        my ( $self, $new, $old ) = @_;
        return 1 if $self->is_dupe( $new, $old );
        return 1 if 'restartsrv cpsrvd' eq $old->full_command();
        return 1 if 'hupcpsrvd' eq $old->command();

        return;
    }

    sub is_valid_args {
        my ( $self, $task ) = @_;
        return 0 == $task->args();
    }

    sub _do_child_task {
        my ( $self, $task, $logger ) = @_;
        $self->checked_system(
            {
                'logger' => $logger,
                'name'   => 'start cpsrvd',
                'cmd'    => '/usr/local/cpanel/etc/init/startcpsrvd',
            }
        );

        return;
    }

    sub deferral_tags {
        my ($self) = @_;
        return qw/restart/;
    }
}

{

    package Cpanel::TaskProcessors::CpServicesTasks::HupCpsrvd;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub is_dupe {
        my ( $self, $new, $old ) = @_;
        my $cmd = $old->full_command();
        return 1 if $new->full_command() eq $cmd;
        return 1 if 'restartsrv cpsrvd' eq $cmd;
        return 1 if 'startcpsrvd' eq $old->command();

        return;
    }

    sub overrides {
        my ( $self, $new, $old ) = @_;
        return $old->command() eq $new->command();
    }

    sub is_valid_args {
        my ( $self, $task ) = @_;
        return 0 == $task->args();
    }

    #
    # Do this in the child and not in the parent
    #
    sub _do_child_task {
        my ( $self, $task, $logger ) = @_;
        eval { require Cpanel::Signal; 1; } or do {
            if ($logger) {
                $logger->throw($@);
            }
            else {
                die $@;
            }
        };
        Cpanel::Signal::send_hup_cpsrvd();

        return;
    }

    sub deferral_tags {
        my ($self) = @_;
        return qw/restart/;
    }
}

{

    package Cpanel::TaskProcessors::CpServicesTasks::RestartSrv;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub overrides {
        my ( $self, $new, $old ) = @_;
        return 1 if $self->is_dupe( $new, $old );

        my $arg = $new->get_arg(0);
        if ( $arg eq 'cpsrvd' ) {
            return 1 if 'startcpsrvd' eq $old->command();
            return 1 if 'hupcpsrvd' eq $old->command();
        }

        return;
    }

    sub is_valid_args {
        my ( $self, $task ) = @_;
        return unless $task->args() >= 1;
        my $srvc = $task->get_arg(0);

        return 1 if -e "/usr/local/cpanel/scripts/restartsrv_$srvc";
        return;
    }

    sub _do_child_task {
        my ( $self, $task, $logger ) = @_;

        my ( $srvc, @args ) = $task->args();

        if ( $srvc eq 'cpanel_php_fpm' ) {

            #
            # The call to restartsrv_cpanel_php_fpm will try to reload it first.
            #
            # However since we call restartsrv cpanel_php_fpm on every account
            # creation and removal this can take quite a bit of time since
            # we have to fork()/exec() restartsrv.
            #
            # We try to do it here first in order to avoid having to call out
            # to the binary.  Ideally in the future we can require in the
            # perl code to do what scripts/restartsrv_* do and avoid
            # the performance issue for all services.
            #
            # In short, we are optimizing for the most frequent call to this
            # module until we have time to do more.
            #

            Cpanel::LoadModule::load_perl_module('Cpanel::Server::FPM::Manager');
            return if eval { Cpanel::Server::FPM::Manager::checked_reload(); };
        }
        elsif ( $srvc eq 'apache_php_fpm' ) {
            push( @args, '--graceful' );
        }

        # Trigger a license state check if we're restarting cpsrvd.
        if ( $srvc eq 'cpsrvd' ) {
            eval {
                # Update the license state if needed.
                require Cpanel::License::State;
                Cpanel::License::State::update_state();
            }
        }

        # should never happen since we control all the input
        # just extra safety
        Cpanel::LoadModule::load_perl_module('Cpanel::Validate::FilesystemNodeName');
        Cpanel::Validate::FilesystemNodeName::validate_or_die($srvc);
        chdir '/';
        my $hash_ar = {
            'logger' => $logger,
            'name'   => "restart $srvc",
            'cmd'    => "/usr/local/cpanel/scripts/restartsrv_$srvc",
        };

        if (@args) {
            $hash_ar->{'args'} = \@args;
        }

        $self->checked_system($hash_ar);

        return;
    }

    sub deferral_tags {
        my ( $self, $task ) = @_;

        my ( $srvc, @args ) = $task->args();
        if ( $srvc =~ /apache/ ) {
            return qw/restart httpd/;
        }

        return qw/restart/;
    }
}

{

    package Cpanel::TaskProcessors::CpServicesTasks::SetupService;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub overrides {
        my ( $self, $new, $old ) = @_;
        return 1 if $self->is_dupe( $new, $old );
        return;
    }

    sub is_valid_args {
        my ( $self, $task ) = @_;
        return unless 2 <= $task->args();
        my $srvc = $task->get_arg(0);
        return 1 if grep { $srvc eq $_ } qw/mailserver ftpserver nameserver/;
        return;
    }

    sub _do_child_task {
        my ( $self, $task, $logger ) = @_;
        my $srvc       = $task->get_arg(0);
        my $newservice = $task->get_arg(1);
        my $disabled   = $task->get_arg(2);
        chdir '/';
        $self->checked_system(
            {
                'logger' => $logger,
                'name'   => "setupservice $srvc",
                'cmd'    => "/usr/local/cpanel/scripts/setup$srvc",
                'args'   => [$newservice],
            }
        );

        # If its disabled we need to run a second time to disable it
        # as we can have the state "service type" with "disabled"
        if ( $disabled && $disabled eq 'disabled' ) {
            $self->checked_system(
                {
                    'logger' => $logger,
                    'name'   => "setupservice $srvc disabled",
                    'cmd'    => "/usr/local/cpanel/scripts/setup$srvc",
                    'args'   => ['disabled'],
                }
            );
        }

        return;
    }

    sub deferral_tags {
        my ($self) = @_;
        return qw/restart/;
    }
}

sub to_register {
    return (
        [ 'startcpsrvd',  Cpanel::TaskProcessors::CpServicesTasks::StartCpsrvd->new() ],
        [ 'restartsrv',   Cpanel::TaskProcessors::CpServicesTasks::RestartSrv->new() ],
        [ 'setupservice', Cpanel::TaskProcessors::CpServicesTasks::SetupService->new() ],
        [ 'hupcpsrvd',    Cpanel::TaskProcessors::CpServicesTasks::HupCpsrvd->new() ],
    );
}

1;
