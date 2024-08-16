package Cpanel::Init::Systemd;

# cpanel - Cpanel/Init/Systemd.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Moo;
use cPstrict;

use Cpanel::Config::Httpd::EA4 ();
use Cpanel::Debug              ();
use Cpanel::Init::Utils        ();

extends 'Cpanel::Init::Initd';

has 'script_permission'          => ( is => 'rw', default => '0644' );
has 'alternate_init_directories' => ( is => 'rw', default => sub { [ '/usr/lib/systemd/system', '/run/systemd/system/', '/lib/systemd/system' ] } );
has '+init_dir'                  => ( is => 'ro', default => '/etc/systemd/system' );

sub install_helpers {

    # disable: cpfunctions on CentOS 7
    return 1;
}

sub _normalize_service_name {
    my ( $self, $service ) = @_;
    return unless defined $service;
    my @div = split '/', $service;
    return $div[-1];
}

sub normalize_service {
    my ( $orig, $self, $service, @args ) = @_;
    return $self->$orig( $self->_normalize_service_name($service), @args );
}

sub _add_dot_service_sufix {
    my ( $self, $service ) = @_;
    my $s = $self->_normalize_service_name($service);
    $s .= '.service' if $s !~ m{\.service$};
    return $s;
}

sub add_service_sufix {
    my ( $orig, $self, $service, @args ) = @_;
    return $self->$orig( $self->_add_dot_service_sufix($service), @args );
}

sub get_script_for_service {
    my ( $self, $service ) = @_;

    $service = $self->_add_dot_service_sufix($service);

    foreach my $dir ( $self->init_dir, @{ $self->alternate_init_directories } ) {
        my $script = $dir . '/' . $service;
        return $script if -e $script;
    }

    return;
}

# enable and disable need to work with sample.service and not sample
around 'CMD_disable' => \&add_service_sufix;
around 'CMD_enable'  => \&add_service_sufix;

sub _service_path {
    my ( $self, $service ) = @_;
    $service =~ s/\.service$//;
    return $self->scripts_dir . $self->service_manager . '/' . $service;
}

# handle directories to install multiple services
sub CMD_install {
    my ( $self, $service ) = @_;

    $service =~ s/\.service$//;

    if ( $service eq 'httpd' && Cpanel::Config::Httpd::EA4::is_ea4() ) {

        # Return ok because there is too much integration and this code
        # goes away with fully EA4 migration.  Message is sufficient to
        # indicate this did nothing.
        return { status => 1, 'message' => 'Installation skipped, this file is now managed by EA4 packages.' };
    }
    my $from = $self->_service_path($service);
    if ( !-e $from && !-e $from . '.service' ) {
        return { status => 0, 'message' => 'The system was unable to install ' . $service . '. The system was unable to find the script in ' . $self->scripts_dir . $self->service_manager . '.' };
    }
    my $reply = { status => 0, message => qq{The system cannot install the service: $service} };

    # only install main service when all subservices succeed
    my $try_to_install_main_service = 1;
    my $subservices                 = $self->_get_subservices_for($service);

    my @need_daemon_reload;

    foreach my $subservice (@$subservices) {

        # first subservice
        if ( $reply->{status} == 0 ) {
            $reply = { status => 1, message => qq{The installation was successful.} };
        }
        Cpanel::Debug::log_info("Installing the $subservice subservice.");
        $reply = $self->SUPER::CMD_install( $subservice, $service );

        if ( $reply->{status} ) {
            push @need_daemon_reload, $subservice if $reply->{'replaced'} || !$reply->{'already_installed'};
        }
        else {
            $try_to_install_main_service = 0;
            last;
        }
    }

    # simple file
    if ( -f $from . '.service' && $try_to_install_main_service ) {
        Cpanel::Debug::log_info("Installing the $service service.");
        $reply = $self->SUPER::CMD_install( $service . '.service' );
        push @need_daemon_reload, $service if $reply->{'status'} && ( $reply->{'replaced'} || !$reply->{'already_installed'} );
    }

    if (@need_daemon_reload) {
        Cpanel::Debug::log_info("Reloading systemd’s unit files. (Updated: @need_daemon_reload)");
        $self->enabler()->daemon_reload();
    }

    return $reply;
}

sub _get_subservices_for {
    my ( $self, $service ) = @_;

    my $from = $self->_service_path($service);
    return [] unless -d $from;

    opendir( my $dh, $from ) or die "The system failed to open the directory $from: $!";
    my @subservices;
    foreach my $subservice ( readdir $dh ) {
        next if $subservice eq '.' || $subservice eq '..';
        if ( $subservice !~ m/\.service$/ ) {
            Cpanel::Debug::log_warn("The '$subservice' subservice file does not end with '.service'.");
            next;
        }
        my $subservice_file = $from . '/' . $subservice;
        if ( !-f $subservice_file || -l $subservice_file ) {
            Cpanel::Debug::log_warn("$subservice_file is not a file.");
            next;
        }
        push @subservices, $subservice;
    }
    closedir($dh) or Cpanel::Debug::log_warn("The system failed to close the directory $from: $!");

    return \@subservices;
}

sub CMD_uninstall {
    my ( $self, $service ) = @_;
    my @need_daemon_reload;

    # 1. try to uninstall current service
    Cpanel::Debug::log_info("Uninstall the '$service' service.");
    my $reply = $self->SUPER::CMD_uninstall( $self->_add_dot_service_sufix($service) );
    push @need_daemon_reload, $service if $reply->{status};

    # 2. uninstall all known subservices for this service
    if ( $reply->{status} ) {
        my $subservices = $self->_get_subservices_for($service);
        foreach my $subservice (@$subservices) {
            Cpanel::Debug::log_info("Uninstall the '$subservice' subservice.");
            my $uninstall_sub = $self->SUPER::CMD_uninstall($subservice);
            push @need_daemon_reload, $subservice if $uninstall_sub->{status};
            $reply = $uninstall_sub if !$uninstall_sub->{status} && $reply->{status};
        }
    }

    # 3. uninstall subservices which are PartOf this one
    # TODO

    if (@need_daemon_reload) {
        Cpanel::Debug::log_info("Reloading systemd’s unit files. (Removed: @need_daemon_reload)");
        $self->enabler()->daemon_reload();
    }

    return $reply;
}

sub cmd {
    my ( $self, $command ) = @_;

    my @path = split( '/', $self->init_script || '' );

    return $self->run_command( $path[-1], $command );
}

sub run_command {
    my ( $self, $service, $command ) = @_;

    $service = $self->_add_dot_service_sufix($service);

    # Give the command 5 seconds to run.
    my $retval;
    eval {
        local $SIG{ALRM} = sub { $retval = { 'status' => 0, 'message' => 'Command timed out.' }; die 'alarm'; };
        my $orig_alrm = alarm $self->maximum_time;
        $retval = Cpanel::Init::Utils::execute( $self->enabler()->systemctl, $command, $service );
        alarm $orig_alrm;
    };
    $retval ||= { 'status' => 0, 'message' => 'Command failed.' };
    $self->status( $retval->{status} );

    return $retval;
}

1;
