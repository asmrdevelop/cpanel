package Cpanel::TaskProcessors::SSLTasks;

#                                      Copyright 2024 WebPros International, LLC
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited.

use cPstrict;

{

    package Cpanel::TaskProcessors::SSLTasks::InstallBestAvailable;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub is_valid_args {
        my ( $self, $task ) = @_;
        return 0 if scalar $task->args() != 1;
        return 1;
    }

    sub _do_child_task {
        my ( $self, $task, $logger ) = @_;

        my $script = '/usr/local/cpanel/bin/install_best_available_certificate_for_domain';
        return unless -x $script;

        local $ENV{'REMOTE_USER'} = 'root';

        my $args_ref = scalar $task->args() ? [ $task->args() ] : undef;

        $self->checked_system(
            {
                'logger' => $logger,
                'name'   => 'install_best_available_certificate_for_domain',
                'cmd'    => $script,
                $args_ref ? ( 'args' => $args_ref ) : (),
            }
        );
        return;
    }

    sub deferral_tags {
        return qw/httpd/;
    }

}

{

    package Cpanel::TaskProcessors::SSLTasks::InstallFromSubQueue;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub is_valid_args ( $self, $task ) {
        return 0 == $task->args();
    }

    sub _do_child_task ( $self, @ ) {
        require Cpanel::SSLInstall::SubQueue::Harvester;
        require Cpanel::SSLInstall::Batch;

        my %username_installs;

        Cpanel::SSLInstall::SubQueue::Harvester->harvest(
            sub ( $vhost_name, $contents_ar ) {
                my ( $username, $key, $crt, $cab ) = @$contents_ar;

                push @{ $username_installs{$username} }, [ $vhost_name, $key, $crt, $cab ];
            }
        );

        for my $username ( sort keys %username_installs ) {
            my $installs_ar = $username_installs{$username};

            my ($results_ar) = Cpanel::SSLInstall::Batch::install_for_user(
                $username,
                $installs_ar,
            );

            for my $i ( 0 .. $#$installs_ar ) {
                my $result_ar = $results_ar->[$i];

                my ( $ok, $msg, $apache_err ) = @$result_ar;

                next if $ok;

                my $err = join( q< >, grep { $_ } $msg, $apache_err );
                warn "SSL installation failed for $installs_ar->[$i][0] (owned by $username): $err";
            }
        }

        return;
    }

    sub deferral_tags {
        return qw/httpd/;
    }
}

{

    package Cpanel::TaskProcessors::SSLTasks::Auto;
    use parent 'Cpanel::TaskQueue::FastSpawn';
    use Cpanel::LoadModule ();

    sub overrides {
        my ( $self, $new, $old ) = @_;

        my $new_is_all_users = !length $new->get_arg(0);
        my $old_is_all_users = !length $old->get_arg(0);

        # We do not want to get a new place in line if a request
        # is made for all users
        return 0 if $new_is_all_users && $old_is_all_users;

        # A request for all users overrides any request for a
        # single user.
        return 1 if $new_is_all_users && !$old_is_all_users;

        # A request for a single user defers any requests
        # for the same user.  Example: when adding 15 subdomains
        # we only want the last on to run so they do not
        # stomp on each other.  This is effectively a debounce
        return 1 if $new->full_command() eq $old->full_command();

        return 0;
    }

    sub is_valid_args {
        my ( $self, $task ) = @_;
        my $numargs = scalar $task->args();
        return 1 if $numargs == 0;
        return 0 if $numargs > 1;
        my ($user) = $task->args();
        Cpanel::LoadModule::load_perl_module('Cpanel::AcctUtils::Account');
        return 1 if Cpanel::AcctUtils::Account::accountexists($user);
        return 0;
    }

    sub _do_child_task {
        my ( $self, $task, $logger ) = @_;

        my $script = '/usr/local/cpanel/bin/autossl_check';
        return unless -x $script;

        my ($user) = $task->args();

        require Cpanel::SSL::Auto::Config::Read;
        return unless Cpanel::SSL::Auto::Config::Read->new()->get_provider();

        $self->checked_system(
            {
                'logger' => $logger,
                'name'   => 'autossl_check',
                'cmd'    => $script,
                'args'   => ( $user ? [ '--user', $user ] : ['--all'] ),
            }
        );
        return;
    }

    sub deferral_tags {
        return qw/httpd/;
    }

}

{

    package Cpanel::TaskProcessors::SSLTasks::AutoRecheck;
    use parent -norequire, 'Cpanel::TaskProcessors::SSLTasks::Auto';
    use Cpanel::LoadModule ();

    # This task allow queuing a future autossl check for a user without it
    # being collapsed into autossl_check by overrides
    sub is_valid_args {
        my ( $self, $task )  = @_;
        my ( $user, @extra ) = $task->args();
        return 0 if !length $user || @extra;
        Cpanel::LoadModule::load_perl_module('Cpanel::AcctUtils::Account');
        return Cpanel::AcctUtils::Account::accountexists($user) ? 1 : 0;
    }

    sub deferral_tags {
        return qw/httpd/;
    }

}

{

    package Cpanel::TaskProcessors::SSLTasks::CheckAllSSLCerts;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    use Try::Tiny;

    use constant _DEFAULT_RETRY_SECONDS => 600;

    sub is_valid_args {
        my ( $self, $task ) = @_;

        my $numargs = scalar $task->args();
        return 1 if $numargs == 0;
        return 0 if $numargs > 1;

        my $retry_secs = _parse_retry_opt( $task->get_arg(0) );
        return 0 unless defined $retry_secs;
        return 0 if $retry_secs < 1;
        return 0 if $retry_secs > 86400;    # 1 day max

        return 1;
    }

    sub overrides {
        my ( $self, $new, $old ) = @_;
        return $self->is_dupe( $new, $old );
    }

    sub _do_child_task {
        my ( $self, $task, $logger ) = @_;

        my $retry_secs = _parse_retry_opt( $task->get_arg(0) );

        my $script      = '/usr/local/cpanel/bin/checkallsslcerts';
        my $script_args = ['--verbose'];

        return unless -x $script;

        require Cpanel::Install::LetsEncrypt;
        my $le_install_status = Cpanel::Install::LetsEncrypt::install();

        my $child_error = try {
            $self->checked_system(
                {
                    'logger' => $logger,
                    'name'   => 'checkallsslcerts',
                    'cmd'    => $script,
                    'args'   => $script_args,
                }
            );
        }
        catch {
            $logger->warn($_);
            1;
        };

        if ( ( !$le_install_status || $child_error ) && $retry_secs ) {
            require Cpanel::ServerTasks;
            Cpanel::ServerTasks::schedule_task( ['SSLTasks'], $retry_secs, 'checkallsslcerts' );
        }
        return;
    }

    sub _parse_retry_opt ($opt) {
        my $seconds;
        if ( length $opt && $opt =~ m{^--retry(?:=(\d+))?$}a ) {
            $seconds = $1 // _DEFAULT_RETRY_SECONDS();
        }
        return $seconds;
    }

    sub deferral_tags {
        return qw/ httpd rpm /;
    }

}

sub to_register {
    return (
        [ 'install_best_available_certificate_for_domain', Cpanel::TaskProcessors::SSLTasks::InstallBestAvailable->new() ],
        [ 'install_from_subqueue',                         Cpanel::TaskProcessors::SSLTasks::InstallFromSubQueue->new() ],
        [ 'autossl_check',                                 Cpanel::TaskProcessors::SSLTasks::Auto->new() ],
        [ 'autossl_recheck',                               Cpanel::TaskProcessors::SSLTasks::AutoRecheck->new() ],
        [ 'checkallsslcerts',                              Cpanel::TaskProcessors::SSLTasks::CheckAllSSLCerts->new() ],
    );
}

1;
__END__

=encoding utf-8

=head1 NAME

Cpanel::TaskProcessors::SSLTasks - Task processor for installing SSL

=head1 VERSION

This document describes Cpanel::TaskProcessors::SSLTasks version 0.0.3


=head1 SYNOPSIS

    use Cpanel::TaskProcessors::SSLTasks;

=head1 DESCRIPTION

Implement the code to install or generate new ssl certificates.

=head1 INTERFACE

This module defines two subclasses of L<Cpanel::TaskQueue::FastSpawn> and a package method.

=head2 Cpanel::TaskProcessors::SSLTasks::to_register

Used by the L<Cpanel::TaskQueue::PluginManager> to register the included classes.

=head2 Cpanel::TaskProcessors::SSLTasks::InstallBestAvailable

Runs install_best_available_certificate_for_domain to install
the best available certificate for a given domain.

=head2 Cpanel::TaskProcessors::SSLTasks::Auto

Runs autossl_check for a given user or all users
if no username is specified.

=head2 Cpanel::TaskProcessors::SSLTasks::AutoRecheck

Runs autossl_check for a given user without being
overridden by autossl_check collapsing duplicate
tasks.

=head2 Cpanel::TaskProcessors::SSLTasks::CheckAllSSLCerts

Runs checkallsslcerts to check the validity of and update the hostname
certificate for supported services.

=head1 CONFIGURATION AND ENVIRONMENT

Cpanel::TaskProcessors::SSLTasks assumes that the environment has been made
safe before any of the tasks are executed.

=head1 DEPENDENCIES

None

=head1 INCOMPATIBILITIES

None reported.

=head1 BUGS AND LIMITATIONS

No bugs have been reported.

=head1 AUTHOR

J. Nick Koston  C<< nick@cpanel.net >>

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2016, cPanel, Inc. All rights reserved.
