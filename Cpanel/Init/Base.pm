package Cpanel::Init::Base;

# cpanel - Cpanel/Init/Base.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Moo;
use cPstrict;

use Carp 'croak';

use File::Basename             ();
use Cpanel::LoadModule         ();
use Cpanel::Config::Httpd::EA4 ();
use Cpanel::Logger             ();
use Cpanel::Init::Utils        ();
use Cpanel::Init::Services     ();
use Cpanel::Init::Enable       ();
use Cpanel::Init::Script       ();
use Cpanel::OS                 ();

# warning Moo predicate returns true on undef, different behavior than the previous Cpanel::Class
has 'init_dir'     => ( is => 'rw', predicate => 'has_init_dir' );
has 'service_name' => ( is => 'rw', predicate => 'has_service_name' );

has 'dep_tree' => (
    is      => 'rw',
    default => sub { Cpanel::Init::Services->new }
);

has 'services' => ( is => 'rw', default => sub { $_[0]->dep_tree->all }, lazy => 1 );
has 'scripts_dir' => ( is => 'rw', default => '/usr/local/cpanel/etc/init/scripts/' );

has 'prog_name' => (
    is      => 'rw',
    lazy    => 1,
    default => sub { ( my $prog_name = File::Basename::basename($0) ) =~ s/^\.\///; return $prog_name }
);

has 'script_gen'        => ( is => 'ro' );
has 'enabler'           => ( is => 'ro' );
has 'status'            => ( is => 'rw', default => 0 );
has 'maximum_time'      => ( is => 'rw', default => 60 );
has 'script_permission' => ( is => 'rw', default => '0755' );
has 'service_manager'   => ( is => 'ro', lazy    => 1, default => sub { Cpanel::OS::service_manager() } );

sub setup_enabler ($self) {

    $self->{'script_gen'} = Cpanel::Init::Script->new( { 'init_dir' => $self->init_dir } );
    $self->{'enabler'}    = Cpanel::Init::Enable->new->factory;

    return;
}

sub generate_scripts {
    my ( $self, $args ) = @_;

    croak 'Arguments must be in a hash.' if ref $args ne 'HASH';

    $self->script_gen->load($args);
    $self->script_gen->build;
    $self->script_gen->install;
    $self->install_helpers;
    $self->add_service( $args->{'service'} );

    return;
}

sub cmd {
    my ( $self, $command ) = @_;

    my $script = $self->init_script;

    if ( -e $script ) {

        # Give the command 5 seconds to run.
        my $retval;
        eval {
            local $SIG{ALRM} = sub { $retval = { 'status' => 0, 'message' => 'Command timed out.' }; die 'alarm'; };
            my $orig_alrm = alarm $self->maximum_time;
            $retval = Cpanel::Init::Utils::execute( $script, $command );
            alarm $orig_alrm;
        };
        $retval ||= { 'status' => 0, 'message' => 'Command failed' };
        $self->status( $retval->{status} );
        return $retval;
    }
    else {
        Cpanel::Logger::cplog( $script . ' not found.', 'info', $self->prog_name );
        die;
    }
}

sub init_script {
    my ($self) = @_;

    croak("You must set the initscript directory and the service name.") if !$self->has_init_dir || !$self->has_service_name;
    return sprintf( "%s/%s", $self->init_dir, $self->service_name );
}

sub CMD_list_all {
    my ($self) = @_;

    my $service = $self->services;

    print '[cpservices managed scripts]' . "\n";
    my $list = join "\n", @{$service};
    print $list . "\n";

    return;
}

sub CMD_install_all {
    my ($self) = @_;

    croak( 'The system cannot find the scripts directory: ' . $self->scripts_dir )
      if !-d $self->scripts_dir;

    my $services = $self->services;

    for my $service ( @{$services} ) {
        $self->service_name($service);

        if ( -d $self->init_dir ) {

            my $from = $self->scripts_dir . $self->service_manager . '/' . $service;
            my $to   = $self->init_dir . '/';
            Cpanel::LoadModule::load_perl_module('File::Copy');
            File::Copy::copy( $from, $to )
              or croak( Cpanel::Logger::cplog( 'The system was unable to copy ' . $service . ' to ' . $to . ': ' . $!, 'info', $self->prog_name ) );

            # Set the permissions on initscripts.
            chmod( oct( $self->script_permission ), $self->init_script );
        }
    }

    return {
        'status'  => 1,
        'message' => 'All scripts successfully installed.',
    };
}

sub CMD_start_all {
    my $self = shift;

    my $services = $self->services();

    for my $service ( @{$services} ) {
        $self->service_name($service);
        $self->cmd('start');
    }

    return {
        'status'  => 1,
        'message' => 'All services successfully started.',
    };
}

sub CMD_stop_all {
    my $self   = shift;
    my $argref = shift;

    my $remove = defined $argref->{'remove'} ? $argref->{'remove'} : 'sshd';

    # Use $remove to take something out of the list.
    $self->remove_service($remove);

    my $services = $self->services();

    for my $service ( reverse @{$services} ) {
        $self->service_name($service);
        $self->cmd('stop');
    }

    return;
}

sub CMD_restart_all {
    my $self = shift;

    # So sshd will be stopped.
    $self->CMD_stop_all( { remove => '' } );
    return $self->CMD_start_all();
}

sub CMD_checkinstall_all {
    my ($self)   = @_;
    my $enabler  = $self->get_enabler_in_reset_state();
    my $services = $self->services();

    $enabler->collect_enable($_) for ( @{$services} );
    return $enabler->enable;
}

# Returns a hashref:
#
#   {
#       status => 0 or 1
#
#       message => '..',
#
#       already_installed => If status==1 indicates whether
#           the intended file was already installed AND identical
#           to the new file.
#
#       replaced => If status==1 indicates whether the new file
#           took the place of a previous file.
#   }
sub CMD_install {
    my ( $self, $service, $opt_main_directory ) = @_;

    croak( 'The system cannot find the scripts directory: ' . $self->scripts_dir ) if !-d $self->scripts_dir;

    if ( $service eq 'httpd' && Cpanel::Config::Httpd::EA4::is_ea4() ) {

        # Return ok because there is too much integration and this code
        # goes away with fully EA4 migration.  Message is sufficient to
        # indicate this did nothing.
        return { status => 1, 'message' => 'Installation skipped, this file is now managed by EA4 packages.' };
    }

    $self->service_name($service);

    $opt_main_directory ||= '';
    $opt_main_directory .= q{/} if $opt_main_directory;

    my $from_basedir = $self->scripts_dir . $self->service_manager . '/' . $opt_main_directory;
    my $from         = $from_basedir . $service;

    if ( !-e $from || -z $from ) {
        return { status => 0, 'message' => 'The system was unable to install ' . $service . '. The system was unable to find the script in ' . $from_basedir . '.' };
    }
    my $to                = $self->init_dir . '/';
    my $already_installed = 0;

    require Cpanel::LoadFile;
    my $old_service_data = Cpanel::LoadFile::load_if_exists("$to/$service");

    if ( $old_service_data && $old_service_data eq Cpanel::LoadFile::load($from) ) {
        $already_installed = 1;
    }
    else {
        Cpanel::LoadModule::load_perl_module('File::Copy');
        File::Copy::copy( $from, $to );
        return {
            'status'  => 0,
            'message' => 'The system was unable to install ' . $service . '. The system was unable to find the script in ' . $from_basedir . '.',
        } if !-e "${to}${service}";
    }

    # Set the permissions on initscripts.
    chmod( oct( $self->script_permission ), $self->init_script );
    $self->add_service($service);

    if ( -e '/var/cpanel/cpservices.yml' ) {
        rename '/var/cpanel/cpservices.yml', '/var/cpanel/cpservices.yaml';
    }
    if ( !-e '/var/cpanel/cpservices.yaml' ) {
        Cpanel::LoadModule::load_perl_module('File::Copy');
        File::Copy::copy( '/usr/local/cpanel/etc/init/scripts/cpservices.yaml', '/var/cpanel/cpservices.yaml' );
    }

    return {
        status            => 1,
        message           => 'The installation succeeded.',
        already_installed => $already_installed,
        replaced          => !$already_installed && !!$old_service_data || 0,
    };
}

sub CMD_uninstall {
    my ( $self, $service ) = @_;

    croak( 'The system cannot find the scripts directory: ' . $self->scripts_dir )
      if !-d $self->scripts_dir;

    my $file = $self->get_script_for_service($service);

    $self->CMD_disable($service);

    if ( defined $file && -e $file ) {
        unlink($file);
    }
    else {
        return { 'status' => 0, 'message' => 'The system was unable to find ' . $service . ' in ' . $self->init_dir };
    }

    if ( !-e $file ) {
        $self->remove_service($service);
        return { 'status' => 1, 'message' => 'The system succeessfully removed the ' . $service };
    }
    else {
        return { 'status' => 0, 'message' => 'The system was unable to find the ' . $service . ' in ' . $self->init_dir };
    }
}

sub all_command {
    my ( $self, $command ) = @_;

    # Add strings to command sent.
    $command = 'CMD_' . $command . '_all';

    # Test to see if the command sent is implemented.
    if ( $self->can($command) ) {

        # Execute the command.
        $self->$command;
        return $self->status();
    }
    else {
        return $self->status();
    }
}

sub run_command_for_one {
    my ( $self, $command, $service, $extra_arg ) = @_;

    $command = 'CMD_' . $command;
    if ( my $module = $self->can($command) ) {
        my $retval = $self->$module( $service, $extra_arg );
        return $retval;
    }
}

sub run_command {
    my ( $self, $service, $command ) = @_;

    my $orig_service = $service;

    my $enabler = $self->get_enabler_in_reset_state();

    # Get services with out file extensions if the subclass add extensions.
    my $services = $self->services( { no_ext => 1 } );

    # Validate service name
    $service = $self->dep_tree->valid_service($service);

    if ($service) {

        my $dep_tree = $self->dep_tree;
        my $deps     = $dep_tree->dependencies_for($service);

        if ( $command eq 'status' ) {
            $service = $self->add_sh($service) if $self->can('add_sh');
            $self->service_name($service);
            return $self->cmd($command);
        }

        # Deal with dependencies.
        # chkservd has too many dependencies to have them start and stop.
        if ( ( scalar @{$deps} > 0 ) && ( $service ne 'chkservd' ) ) {

            # More than one dependency?
            if ( scalar @{$deps} > 1 ) {
                printf '%s has %s as dependencies.' . "\n", $service, Cpanel::Init::Utils::commify_series( @{$deps} );
            }
            else {
                printf '%s has %s as a dependency.' . "\n", $service, Cpanel::Init::Utils::commify_series( @{$deps} );
            }

            for my $item ( @{$deps}, $service ) {
                $item = $self->add_sh($item) if $self->can('add_sh');

                $self->service_name($item);
                return $self->cmd($command);
            }
        }
        else {
            $service = $self->add_sh($service) if $self->can('add_sh');
            $self->service_name($service);
            return $self->cmd($command);
        }
    }
    else {
        $service = $self->can('add_sh') ? $self->add_sh($orig_service) : $orig_service;
        $self->service_name($service);
        if ( -e $self->init_script ) {
            return $self->cmd($command);
        }
        elsif ( $self->can('add_sh') ) {
            $self->service_name($orig_service);
            if ( -e $self->init_script ) {
                return $self->cmd($command);
            }
            else {
                return { 'status' => 0, 'message' => $service . ' not found.', 'info', $self->prog_name };
            }
        }
        else {
            return { 'status' => 0, 'message' => $service . ' not found.', 'info', $self->prog_name };
        }
    }
    return { 'status' => 0 };
}

sub has_service {
    my ( $self, $service ) = @_;
    return if !$service;
    return grep { $_ eq $service } @{ $self->services };
}

sub add_service {
    my ( $self, $service, $dependencies ) = @_;
    $dependencies ||= [];

    my $dup = grep { $_ eq $service } @{ $self->services };

    # Do nothing if there is a duplicate.
    return if $dup;

    my $retval = $self->dep_tree->add( $service, $dependencies );
    if ($retval) {
        $self->services( $self->dep_tree->all );
        return $self->status(1);
    }
    return $self->status(0);
}

sub remove_service {
    my ( $self, $service ) = @_;

    # Remove $service from the list of services.
    my $retval = $self->dep_tree->remove($service);
    if ($retval) {
        $self->services( $self->dep_tree->all );
        return $self->status(1);
    }
    return $self->status(0);
}

# return false when do not exists
sub get_script_for_service {
    my ( $self, $service ) = @_;

    my $s = $self->init_dir . '/' . $service;
    return $s if -e $s;
    if ( $self->can('add_sh') ) {
        $s = $self->init_dir . '/' . $self->add_sh($service);
        return $s if -e $s;
    }
    return;
}

sub get_enabler_in_reset_state {
    my ($self) = @_;

    my $enabler = $self->enabler;

    # Now reset the state of the enabler
    # object so there are no services
    # collected in the internal
    # 'enabled' and 'disabled'
    # arrayrefs (See Cpanel::Init::Enable::Base)
    $enabler->reset();

    return $enabler;
}

sub checkinstall {
    my ( $self, $service, $levels ) = @_;

    if ( !defined $self->get_script_for_service($service) ) {
        return { 'status' => 0, 'message' => 'The service init script does not exist at ' . $self->init_dir . '/' . $service };
    }

    my $enabler = $self->get_enabler_in_reset_state();
    $enabler->collect_enable($service);
    my $retval = $enabler->enable($levels);    # enable returns is_enabled
    return $self->status($retval);
}

sub install_helpers {
    return 1;
}

sub CMD_enable {
    goto &checkinstall;
}

sub CMD_disable {
    my ( $self, $service, $levels ) = @_;
    my $enabler = $self->get_enabler_in_reset_state();

    if ( !defined $self->get_script_for_service($service) ) {
        return $self->status(0);
    }

    $enabler->collect_disable($service);
    $enabler->disable($levels);
    my $retval = $enabler->is_enabled($service);
    return $self->status( !$retval );
}

sub CMD_add {
    my ( $self, $service ) = @_;

    if ( !defined $self->get_script_for_service($service) ) {
        return $self->status(0);
    }

    return $self->add_service($service);
}

sub CMD_remove {
    my ( $self, $service ) = @_;

    if ( !defined $self->get_script_for_service($service) ) {
        return $self->status(0);
    }
    $self->remove_service($service);
    return $self->status(1);
}

1;

__END__

=head1 NAME

Cpanel::Init::Base - [Base class for OS specific subclasses]

=head1 VERSION

    This document describes Cpanel::Init::Base

=head1 DESCRIPTION

    This module provides the general methods that all the operating system specific subclasses
    can use. If an operating system subclass needs different functionality they can overwrite
    the method in the subclass. All subclass must set the set_init_dir to the
    appropriate init directory for the operating system.

=head1 PUBLIC INTERFACE

=head2 Methods

=over 4

=item all_command

Argument list: $command

If you pass start, stop or status to this method it will run that command for all the services.

=item run_service

Arugment list: $service_name, $command

The method get the correct directory for $service_name and pass command to it.

=item add_service

Argument list: $service

Adds a service to the list of services.

=item remove_service

Argument list: $service

Removes a service from the list of services.

=item has_service

Argument list: $service

Returns a boolean if the service is in the dep tree

=item checkinstall

    Argument list: $service_name

    This method will enable the the given service in a operating system spefic manner.

=back

=head1 PROTECTED INTERFACE

=head2 Methods

=over 4

=item cmd

Argument list: $command

This method calls init_script to get the full location to the initscript
which needs to be given to set_service_name prior to call cmd.

=item init_script

Argument list: none

This method combines and returns the results from get_init_dir and get_service_name
with a / between them.

=item CMD_start_all

Argument list: none

This method calls start on all of the services in get_services.

=item CMD_stop_all

Argument list: {remove => 'service'}

This method calls stop on all of the services in get_services. By default,
this method will not stop sshd. If a hash reference that contains a key of 'remove'
is passed in to it will remove that service instead. If you wish all the services
to run pass a empty string as the value.

=item CMD_list_all

Argument list: none

List all initscripts that are managed

=item CMD_install_all

This method will install all of the services to initscript directory for
the running operating system.

=item CMD_checkinstall_all

This method will enable all the services in a operating system spefic manner.

=item set_init_dir

Argument list: $dir

This method sets the base directory for the init scripts.

=item get_init_dir

Argument list: none

This method returns the base directory for the init scripts.

=item set_service_name

Argument list: $service_name

This method sets the script name for the service.

=item get_service_name

Argument list: none

This method returns the script name for the service.

=item set_services

Argument list: $array_ref

This method takes an array reference of script names.

=item get_services

Argument list: none

This method returns an array reference of script names.

=back
