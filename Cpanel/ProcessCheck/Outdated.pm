package Cpanel::ProcessCheck::Outdated;

# cpanel - Cpanel/ProcessCheck/Outdated.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Try::Tiny;

use Cpanel::Binaries                 ();
use Cpanel::Exception                ();
use Cpanel::LoadModule               ();
use Cpanel::OS                       ();
use Cpanel::ServiceManager::Mapping  ();
use Cpanel::SafeRun::Object          ();
use Cpanel::Services::Dormant::Utils ();

use Cpanel::Debug ();

#These are services we skip over because there’s no Service Manager
#module for them--or, in the case of “imap” and “pop”, because we’ve
#already covered Dovecot as “lmtp”.
#
#Referenced in tests.
use constant _C6_NO_SERVICE_MANAGER_MODULE => qw{
  imap
  pop
  exim-altport
  syslogd
  tomcat
};

use constant SERVICES_TO_IGNORE => qw{
  auditd
  cpanel
  cpanellogd
  cpdavd
  cpgreylistd
  cpsrvd
  dbus
  dbus-broker
  dnsadmin
  NetworkManager
  network
  queueprocd
  spamd
  tailwatchd
};

my $local_exclude_file = '/etc/cpanel/local/ignore_outdated_services';

###
### Public API
###

sub outdated_processes {
    die Cpanel::Exception::create('RootRequired') unless _running_as_root();

    my $outdated_processes_check_method = Cpanel::OS::outdated_processes_check();

    if ( $outdated_processes_check_method eq 'checkrestart' ) {
        return _outdated_processes_checkrestart()->@*;
    }
    else {    # default
        return _outdated_processes_default()->@*;
    }
}

sub outdated_services {
    die Cpanel::Exception::create('RootRequired') unless _running_as_root();

    my $outdated_services_check_method = Cpanel::OS::outdated_services_check();

    my $services;
    if ( $outdated_services_check_method eq 'centos6' ) {
        $services = _outdated_services_for_centos6();
    }
    elsif ( $outdated_services_check_method eq 'needrestart_b' ) {
        $services = _outdated_services_needrestart_b();
    }
    else {    # default
        $services = _outdated_services_default();
    }

    return _filter_services($services)->@*;
}

sub reboot_suggested {
    die Cpanel::Exception::create('RootRequired') unless _running_as_root();

    my $check_reboot_method = Cpanel::OS::check_reboot_method();

    if ( $check_reboot_method eq 'unsupported' ) {
        die Cpanel::Exception::create(
            'Unsupported',                                        #
            'Reboot recommendations not provided for “[_1]”.',    #
            [ Cpanel::OS::display_name() ]                        #
        );
    }
    elsif ( $check_reboot_method eq 'check-reboot-required' ) {
        return _reboot_suggested_using_reboot_required_file();
    }

    # default case
    return _reboot_suggested_default();
}

###
### Internal helpers
###

sub _outdated_processes_checkrestart() {
    my @pids;

    # on debian uses /usr/sbin/checkrestart from debian-goodies

    my $proc = Cpanel::SafeRun::Object->new( program => q[/usr/sbin/checkrestart] );

    $proc->die_if_error() if $proc->signal_code();
    _handle_stderr( $proc, warn_only => 1 );

    if ( my $out = $proc->stdout() ) {
        foreach my $line ( split m/\n/, $out ) {
            if ( $line =~ m/^\s+(\d+)\s+/a ) {
                push @pids, $1;
            }
        }
    }

    return \@pids;
}

sub _outdated_processes_default() {
    my $proc = Cpanel::SafeRun::Object->new( program => _get_exec() );

    $proc->die_if_error() if $proc->signal_code();
    _handle_stderr($proc);

    my @pids;
    if ( my $out = $proc->stdout() ) {

        # In CentOS 6, needs-restarting displays /proc/##/cmdline exactly as
        # is; however, CentOS 7 replaces NULs with spaces for readability.  The
        # CentOS 7 approach means we can't recover the original command, since
        # spaces could be part of the arguments or could be between.  Since
        # there is inconsistency, just grab the PID and let the caller
        # determine the command through their preferred method.
        foreach my $line ( split m/\n/, $out ) {

            # ignore empty lines
            next if $line =~ m{^[ \t\0]*$};

            die Cpanel::Exception->create( 'The system received unexpected output from “[_1]”: [_2]', [ _get_exec(), $line ] ) if $line !~ m/^(\d+) : /a;
            push @pids, $1;
        }
    }

    return \@pids;

}

sub _reboot_suggested_default() {

    my $proc = Cpanel::SafeRun::Object->new(
        program => _get_exec(),
        args    => ['--reboothint'],
    );

    $proc->die_if_error() if $proc->signal_code();
    _handle_stderr($proc);

    return                if !$proc->error_code();
    $proc->die_if_error() if $proc->error_code() != 1;    # Unexpected error code

    my %core;
    foreach my $line ( split m/\n/, $proc->stdout() ) {
        if ( $line =~ m/^\s+(\S+) -> (.*)$/ ) {
            $core{$1} = $2;
        }
        elsif ( $line =~ qr{^\s+\*\s(\S+)$} ) {
            $core{$1} = 1;    # use '1' as value
        }
    }

    return unless scalar keys %core;

    return \%core;
}

sub _reboot_suggested_using_reboot_required_file() {

    my $reboot_required_file = q[/var/run/reboot-required];

    return unless -e $reboot_required_file;

    # API expect a list of packages triggering the restart
    # view _reboot_suggested_default output
    # kernel is special

    if ( open( my $fh, '<', $reboot_required_file ) ) {
        foreach my $line ( readline $fh ) {
            if ( $line =~ m{\Q*** System restart required ***\E} ) {
                return { system => 1 };    # whatever value here
            }
        }
    }

    return;
}

sub _filter_services ($services) {

    $services //= [];

    # Dormant services may be shown as outdated due to the process going dormant (or waking up)
    # cpsrvd is ALWAYS added to this list because its PID rarely changes (so it is listed as a false positive due to how the needs-restarting script determines the outdated processes)
    # cpsrvd is 'cpanel.service' on Centos7 in systemd

    my %enabled_dormant_services = map { ( "$_.service" => 1 ) } (    #
        Cpanel::Services::Dormant::Utils::get_enabled_dormant_services(),    #
        'cpsrvd', 'cpanel'                                                   #
    );

    my %ignore_services = map { ( "$_.service" => 1 ) } (                    #
        SERVICES_TO_IGNORE(), _load_custom_ignores()                         #
    );

    return [ grep { !$enabled_dormant_services{$_} && !$ignore_services{$_} } $services->@* ];
}

# Provides a way for  customers and integrators to exclude processes
# and services from our restarts triggered by system changes.
sub _load_custom_ignores {
    my @ignore = ();

    require Cpanel::LoadFile;

    if ( _custom_excludes_exists() ) {
        foreach my $service ( @{ Cpanel::LoadFile::loadfileasarrayref($local_exclude_file) } ) {
            next if $service =~ m{^[ \t\0]*$};
            next if $service =~ m{^#};
            chomp $service;
            push( @ignore, $service );
        }
    }
    return @ignore;
}

sub _running_as_root() {    # For testing
    return $> == 0;
}

sub _system_supports_smaps() {    # For testing
    return -e "/proc/$$/smaps";
}

sub _custom_excludes_exists() {    # for testing
    return -f $local_exclude_file;
}

sub _get_exec() {

    state $bin;

    return $bin if $bin;

    # needs-restarting won't work without smaps support (Disabled in grsec kernels).
    die Cpanel::Exception::create( 'Unsupported', 'The kernel does not support [asis,smaps].' ) unless _system_supports_smaps();

    # HB-5743: needs-restarting on CentOS 8 now uses DNF and appears to be more performant/less buggy.
    # For now we are trying it out on 8 until such time as we see issues related to this.

    return $bin = Cpanel::Binaries::path('needs-restarting');
}

sub _outdated_services_default {

    my @outdated;

    my $program = _get_exec();
    my $proc    = Cpanel::SafeRun::Object->new(
        program => $program,
        args    => ['--services'],
    );
    $proc->die_if_error();
    _handle_stderr( $proc, warn_only => 1 );

    if ( my @lines = split m/\n/, $proc->stdout() ) {

        # https://github.com/rpm-software-management/yum-utils/issues/27
        # ^^ This is fixed but not in CentOS 7; the following logic
        # accommodates the problem.

        require Cpanel::Systemd;

        my $services_ar = Cpanel::Systemd::get_service_names_ar();

        for my $line (@lines) {
            if ( grep { $line eq "$_.service" } @$services_ar ) {
                push @outdated, $line;
            }
            elsif ( $line =~ m<\S> ) {
                Cpanel::Debug::log_warn($line);
            }
        }
    }

    return \@outdated;
}

sub _outdated_services_needrestart_b() {
    my @outdated;

    my $proc = Cpanel::SafeRun::Object->new(
        program => q[/usr/sbin/needrestart],
        args    => ['-b'],
    );
    $proc->die_if_error();

    my @lines = split m/\n/, $proc->stdout();
    foreach my $line (@lines) {
        if ( $line =~ qr{^NEEDRESTART-SVC:\s+(.+\.service)} ) {
            push @outdated, $1;
        }
    }

    return \@outdated;
}

# Certain ServiceManager objects, like Exim (the only one I'm aware of atm), don't have a pidfile on centos 6. Please see that/those modules for details.
sub _GET_CENT6_SERVICES_LACKING_PIDFILE_IN_OBJECT {
    return ( exim => '/var/spool/exim/exim-daemon.pid' );
}

#NOTE: This may be useful to factor out into something
#separately reusable since it bridges the logic between
#WHM’s tracking of services and Cpanel::ServiceManager.
sub _outdated_services_for_centos6 {
    my @outdated_pids = outdated_processes();

    return [] unless @outdated_pids;

    my %outdated_pid_lookup;
    @outdated_pid_lookup{@outdated_pids} = ();

    Cpanel::LoadModule::load_perl_module('Cpanel::Services::List');
    Cpanel::LoadModule::load_perl_module('Cpanel::LoadFile');
    Cpanel::LoadModule::load_perl_module('Cpanel::ServiceManager');
    Cpanel::LoadModule::load_perl_module('Cpanel::Autodie');

    #It returns key/value pairs or a hashref, despite the name.
    my %svc_setup = Cpanel::Services::List::get_service_list();

    my @outdated_svcs;

    #This translates a service name as Cpanel::Services refers to it
    #into a name as Cpanel::ServiceManager recognizes it. Note that
    #Dovecot is represented here as LMTP since that service is always on.
    my %SERVICE_NAME_FOR_SERVICE_MANAGER = Cpanel::ServiceManager::Mapping::get_service_name_to_service_manager_module_map()->%*;

    my %CENT6_SERVICES_LACKING_PIDFILE_IN_OBJECT = _GET_CENT6_SERVICES_LACKING_PIDFILE_IN_OBJECT();

    delete @svc_setup{ _C6_NO_SERVICE_MANAGER_MODULE() };
    delete @svc_setup{ SERVICES_TO_IGNORE() };

    for my $svc ( sort keys %svc_setup ) {
        my $sm_svc = $SERVICE_NAME_FOR_SERVICE_MANAGER{$svc} || $svc;

        # the chkserv.d directory is loaded for service names and altport exim may be enabled which can look like: exim-26,29,42
        # you can't have altport exim without exim being enabled, so just skip
        next if index( $sm_svc, 'exim-' ) == 0 && $sm_svc =~ /\Aexim-[0-9,]+\z/;

        # FTP may be disabled
        next if $sm_svc eq 'disabled';

        my $svc_obj;
        try {
            $svc_obj = Cpanel::ServiceManager->new( service => $sm_svc );
        }
        catch {
            if ( try { $_->isa('Cpanel::Exception::Services::Unknown') } ) {
                Cpanel::Debug::log_warn("$svc has no corresponding init script. Skipping...\n");
            }
            else {
                Cpanel::Debug::log_warn("$svc: $_");
            }
        };

        next unless $svc_obj;

        try {
            my $pidfile = $svc_obj->pidfile();
            $pidfile = $CENT6_SERVICES_LACKING_PIDFILE_IN_OBJECT{$sm_svc} if !length $pidfile && $CENT6_SERVICES_LACKING_PIDFILE_IN_OBJECT{$sm_svc};
            if ( $pidfile && Cpanel::Autodie::exists($pidfile) ) {
                my $pid = Cpanel::LoadFile::load($pidfile);
                chomp $pid;
                if ( exists $outdated_pid_lookup{$pid} ) {

                    #Make this match the return from CentOS 7’s
                    #“needs-restarting --services” command.
                    push @outdated_svcs, "$sm_svc.service";
                }
            }
        }
        catch {
            local $@ = $_;
            Cpanel::Debug::log_warn("_outdated_services_for_centos6: $@");
        };
    }

    return \@outdated_svcs;
}

sub _handle_stderr ( $proc, %opts ) {

    # CPANEL-29407: Expand list of expected errors to include some internal
    # yum issues. Some of these are emitted by yum itself, while others are
    # re-reported errors from the underlying URLGrabber library.

    if ( !$opts{warn_only} ) {
        if ( grep { !_expected_error($_) } split m/\n/, $proc->stderr() // '' ) {
            die Cpanel::Exception::create(
                'ProcessFailed',
                [
                    stdout => $proc->stdout(),
                    stderr => $proc->stderr(),
                ]
            );
        }
    }

    if ( my $err = $proc->stderr() ) {
        Cpanel::Debug::log_warn($err);
    }

    return;
}

sub _expected_error ($error_string) {

    my @expected_errors = (
        qr{^Failed to read PID \d+'s smaps\.$}a,
        qr{^Could not open /proc/\d+/}a,
        qr{^Cannot retrieve repository metadata},
        qr{^Could not get metalink},
        qr{^\d+: }a,
        qr{^(rpmdb|Config|pkgsack) time:},
        qr{Reading Local RPMDB},
        qr{Setting up Package Sacks},
        qr{is listed more than once},
        qw{Tried to add None},
    );

    for my $error (@expected_errors) {
        if ( $error_string =~ m{$error} ) {
            return 1;
        }
    }

    return 0;
}

1;

__END__

=encoding UTF-8

=head1 NAME

Cpanel::ProcessCheck::Outdated - Module to check if processes are up to date

=head1 SYNOPSIS

    use Cpanel::ProcessCheck::Outdated ();

    my @PIDs = Cpanel::ProcessCheck::Outdated::outdated_processes();
    my @srvcs = Cpanel::ProcessCheck::Outdated::outdated_services();
    my $reboot = Cpanel::ProcessCheck::Outdated::reboot_suggested();

=head1 DESCRIPTION

When updating the system, e.g. with C<yum update>, the on-disk copies of
libraries and binaries may be changed.  This means that all processes started
in the future will be running the updated version.  However, currently running
processes usually maintain an open handle to the original binary and dependent
libraries, and thus do not receive the benefits of the update (which may
include security patches).  To use the updated files, the processes must be
restarted.

This module provides an interface to query what needs to be restarted to get
the full benefit of the updates (which may include a full system restart).

=head1 FUNCTIONS

=head2 C<< outdated_processes() >>

Gets the processes that need to be restarted because they are running with old
binaries or libraries that have since been updated on disk (but not in the
process' memory).

These processes should be restarted to get the full effect of updates to the
system.

B<Returns:> An array of PIDs that need to be restarted; the array will be empty
if no processes require restart.

B<Dies:> with

=over

=item C<Cpanel::Exception>

When unexpected output that cannot be parsed is received on STDOUT.

=item C<Cpanel::Exception::ProcessFailed>

When unexpected output is received on STDERR.

=item C<Cpanel::Exception::ProcessFailed::Signal>

When the process dies with a signal before completing.

=item C<Cpanel::Exception::ProcessFailed::Error>

When the process exits with an unexpected error code.

=item C<Cpanel::Exception::RootRequired>

When the current EUID is not root.

=item C<Cpanel::Exception::Service::BinaryNotFound>

When the program to check for outdated processes cannot be found.

=item C<Cpanel::Exception::Unsupported>

When the system doesn't support checking for outdated processes.

This can occur on systems that do not supply smaps to other processes, which
can occur on hardened kernels like Grsecurity®.

=back

=head2 C<< outdated_services() >>

Gets the systemd services that need to be restarted because the underlying
processes are running with old binaries or libraries that have since been
updated on disk (but not in the process' memory).

These services should be restarted to get the full effect of updates to the
system.

B<Note:> This function only works on CentOS 7 or later.

B<Returns:> An array of services that need to be restarted; the array will be
empty if no services require restart.

B<Dies:> with

=over

=item C<Cpanel::Exception::ProcessFailed>

When unexpected output is received on STDERR.

=item C<Cpanel::Exception::ProcessFailed::Signal>

When the process dies with a signal before completing.

=item C<Cpanel::Exception::ProcessFailed::Error>

When the process exits with an unexpected error code.

=item C<Cpanel::Exception::RootRequired>

When the current EUID is not root.

=item C<Cpanel::Exception::Service::BinaryNotFound>

When the program to check for outdated processes cannot be found.

=item C<Cpanel::Exception::Unsupported>

When the system doesn't support checking for outdated services.

This can occur on systems that do not supply smaps to other processes, which
can occur on hardened kernels like Grsecurity®.  It will also occur on CentOS 6
systems, as that release doesn't use systemd.

=back


=head2 C<< reboot_suggested() >>

Provides a suggestion on when to reboot the system, rather than restart
individual services.

If core libraries are updated, it often makes more sense to reboot the entire
system instead of restart individual services.  This can be because critical
services that shouldn't be stopped are affected (like systemd) or because most
of the services would require restart (potentially in order), which could make
the system less stable.

B<Note:> This function only works on CentOS 7 or later.

B<Returns:> C<undef> if a reboot is B<not> suggested; a HASHREF if a reboot is
suggested.  If the HASHREF has values, the keys are the core libraries that
were updated and the values are the versions of those core libraries.

B<Dies:> with

=over

=item C<Cpanel::Exception::ProcessFailed>

When unexpected output is received on STDERR.

=item C<Cpanel::Exception::ProcessFailed::Signal>

When the process dies with a signal before completing.

=item C<Cpanel::Exception::ProcessFailed::Error>

When the process exits with an unexpected error code.

=item C<Cpanel::Exception::RootRequired>

When the current EUID is not root.

=item C<Cpanel::Exception::Service::BinaryNotFound>

When the program to check for outdated processes cannot be found.

=item C<Cpanel::Exception::Unsupported>

When the system doesn't support checking core libraries.

This can occur on systems that do not supply smaps to other processes, which
can occur on hardened kernels like Grsecurity®.  It will also occur on CentOS 6
systems, as that version doesn't provide a useful hint based on core libraries.

=back

=cut
