
# cpanel - Cpanel/ServiceManager/Services/Apache_php_fpm.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::ServiceManager::Services::Apache_php_fpm;

use strict;

use Moo;
use Cpanel::PHPFPM::Controller ();
use Cpanel::PsParser           ();
use Cpanel::Exception          ();

extends 'Cpanel::ServiceManager::Base';

# We don't have a single pid file, or a single startup binary or command line regex, etc, since this handles multiple daemons, sub daemons, etc
has '+suspend_time' => ( is => 'ro', default => 30 );

=head1 NAME

Cpanel::ServiceManager::Services::Apache_php_fpm

=head1 SYNOPSIS

restartsrv driver for the 'apache_php_fpm' service.

=head1 DESCRIPTION

    exec('/usr/local/cpanel/scripts/restarsrv_apache_php_fpm');

=head1 SUBROUTINES

=head2 stop

Stops the service. Returns 1 unless something throws an exception.

=cut

sub stop {
    my ( $self, %opts ) = @_;
    return $self->_do_action( "stop", \%opts );
}

=head2 start

Starts the service. Returns 1 unless something throws an exception.

=cut

sub start {
    my ( $self, %opts ) = @_;
    return $self->_do_action( "start", \%opts );
}

=head2 restart

Re-starts the service. Returns 1 except in two cases:
* No PHP-FPM packages are installed. The return here is -1.
* Something throws an exception.

=cut

sub restart {
    my ( $self, %opts ) = @_;

    my $action = $opts{'graceful'} ? 'restart_gracefully' : 'restart';
    return $self->_do_action( $action, \%opts );
}

sub _do_action {
    my ( $self, $action, $opts_hr ) = @_;

    my $versions_ar   = Cpanel::PHPFPM::Controller::get_phpfpm_versions();
    my $versions_used = Cpanel::PHPFPM::Controller::get_phpfpm_versions_in_use();

    if ( !@{$versions_ar} ) {
        print "\nThere are no PHP-FPM packages installed for Apache.\n\n" if !$opts_hr->{'suppress_output'};
        return -1;    # this is not a failure, there is simply nothing to do so do not return false.
    }

    $self->service_status( sprintf( "Found %d versions of PHP-FPM: @{$versions_used}", scalar @{$versions_used} ) );

    my @failed_versions = _process_actions_for_versions( $action, $versions_ar );
    return 1 if !@failed_versions;

    # an fpm pool threw an exception, lets check for cruft files and try the action again.
    require Cpanel::PHPFPM::Inventory;
    if ( my $renamed_files = Cpanel::PHPFPM::Inventory::fix_cruft() ) {
        foreach my $conf_file ( keys %{$renamed_files} ) {
            if ( $renamed_files->{$conf_file}{new} ) {
                warn "[INFO] Renamed invalid config file $conf_file to $renamed_files->{$conf_file}{new}\n" if !$opts_hr->{'suppress_output'};
            }
            elsif ( $renamed_files->{$conf_file}{error} ) {
                warn "[ERROR] Failed to rename invalid config file $conf_file: $renamed_files->{$conf_file}{error}\n" if !$opts_hr->{'suppress_output'};
            }
        }
        @failed_versions = _process_actions_for_versions( $action, \@failed_versions );
        return 1 if !@failed_versions;
    }

    # special edge case if we are on virtuozzo and one or more accounts are
    # overquota CPANEL-27461

    require Cpanel::OSSys::Env;
    require Cpanel::FileUtils::Move;

    if ( Cpanel::OSSys::Env::get_envtype() =~ m/virtuozzo/i ) {
        my @moves;

        my $ref = Cpanel::PHPFPM::Inventory::get_inventory();

        my @users = keys %{$ref};
        foreach my $user (@users) {
            next if ( $user eq "orphaned_files" || $user eq "cruft" );

            my $user_ref    = $ref->{$user};
            my $domains_ref = $user_ref->{'domains'};

            foreach my $domain ( keys %{$domains_ref} ) {
                my $dref       = $domains_ref->{$domain};
                my $phpversion = $dref->{'phpversion'};

                next if ( !$dref->{is_overquota} );

                my $conf_file      = $dref->{conf_files}->[0]->{file};
                my $save_conf_file = $conf_file . '.moved_to_allow_fpm_to_restart';

                push(
                    @moves,
                    {
                        user        => $user,
                        domain      => $domain,
                        source_file => $conf_file,
                        moved_file  => $save_conf_file,
                    }
                );

                Cpanel::FileUtils::Move::safemv( '-f', $conf_file, $save_conf_file );
            }
        }

        if (@moves) {
            @failed_versions = _process_actions_for_versions( $action, \@failed_versions );

            foreach my $move (@moves) {
                Cpanel::FileUtils::Move::safemv( $move->{moved_file}, $move->{source_file} );
            }

            # send out an icontact to the administrator

            require Cpanel::Notify;
            foreach my $move (@moves) {
                Cpanel::Notify::notification_class(
                    'class'            => 'PHPFPM::AccountOverquota',
                    'application'      => 'PHPFPM::AccountOverquota',
                    'constructor_args' => [
                        'origin'     => 'restartsrv',
                        'conf_file'  => $move->{source_file},
                        'moved_file' => $move->{moved_file},
                        'user'       => $move->{user},
                        'domain'     => $move->{domain},
                    ]
                );
            }

            return 1 if !@failed_versions;
        }
    }

    # return undef if no versions were successful.
    return if @failed_versions == @{$versions_ar};

    # Something failed but at least one version was successful.
    return @failed_versions ? 0 : 1;
}

sub _process_actions_for_versions {
    my ( $action, $versions ) = @_;

    my @failed_versions;

    foreach my $version ( @{$versions} ) {
        eval { Cpanel::PHPFPM::Controller::process_action( $version, $action ) };
        my $err = $@;
        if ($err) {
            warn "[ERROR] $err\n";
            push( @failed_versions, $version );
        }
    }

    return @failed_versions;
}

=head2 support_reload

Since 'reload' is an alias for 'restart' for this service, just returns 1.

=cut

# In PHP-FPM's case, reload is equivalent to a graceful restart,
# as the same process is required to reload the configuration in the worker processes.
# Alias it as such.
*reload = *reload = \&restart;
sub support_reload { return 1; }

=head2 status

Returns the number of errors encountered when probing the pools to see if there is a problem or blank string if everything is OK.

=cut

# For status, we can just check the main php-fpm processes
sub status {
    my ($self)        = @_;
    my $vers_ar       = Cpanel::PHPFPM::Controller::get_phpfpm_versions();
    my $process_table = Cpanel::PsParser::fast_parse_ps( 'resolve_uids' => 0, 'exclude_self' => 1, 'exclude_kernel' => 1 );

    # Error status is always printed on greatSuccess by restartsrv_base. Make sure it is blank string if falsey
    my $error_status = "";
    my @errors;
    foreach my $version ( @{$vers_ar} ) {
        my $user_config_count = Cpanel::PHPFPM::Controller::phpfpm_version_users_configured($version);
        if ( $user_config_count > 0 ) {
            my $running = 0;
            my ( $cmd, $pid, $user );
            foreach my $process ( @{$process_table} ) {
                if ( $process->{'command'} =~ m/php-fpm:\s+master\s+process\s+\(.+\/ea-php$version\/.+conf/ and $process->{'uid'} == 0 ) {
                    $running++;
                    $cmd  = $process->{'command'};
                    $pid  = $process->{'pid'};
                    $user = 'root';
                    last;
                }
            }
            if ($running) {
                print "Apache PHP-FPM $version($cmd) is running as $user with PID “$pid” (process table check method)\n";
            }
            else {
                $error_status++;
                push( @errors, Cpanel::Exception::create( 'Service::IsDown', [ 'service' => "Apache PHP-FPM $version" ] )->to_string() . "\n" );
            }
        }
    }
    if (@errors) {
        die @errors;
    }
    return $error_status;
}

=head2 check

Checks how things are doing. Returns 1 if A-OK, dies if the status subroutine threw.

=cut

# The status check is really all we want now, to see if the master process PIDs are running. See HB-2629
# *check = \&status;
sub check {

    # Hide the status check messages until we are ready to show the success or error messages
    my $stdout;
    my $orig = *STDOUT;
    local *STDOUT;
    open( STDOUT, ">", \$stdout ) or warn "Could not redirect STDOUT\n";
    eval { status(); };
    open( STDOUT, '>&', \$orig ) or warn "Could not redirect STDOUT\n";
    if ($@) {
        die $@;
    }
    return 1;
}

sub check_with_message {
    my ($self) = @_;

    # check_with_message is supposed to return ( $status, $msg ) but will work without it
    # In the future this should be improved to return a useful message
    return $self->check();
}

1;
