
# cpanel - Cpanel/RestartSrv/Systemd.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::RestartSrv::Systemd;

use strict;
use warnings;

use Cpanel::SafeRun::Errors ();
use Cpanel::OS              ();

my @needs_systemd_show_keys = qw(LoadState FragmentPath ActiveState MainPID SubState PIDFile UnitFileState Type CanStart ExecMainCode ExecMainStatus);

sub get_service_info_via_systemd {
    my $p_service = shift;

    my $s = $p_service;
    $s .= '.service' if length($s) < 9 || substr( $s, -8 ) ne '.service';

    local $ENV{'LANG'} = 'C';
    local $ENV{'TZ'}   = 'UTC';
    my %info =                                 #
      map { ( split( m/=/, $_ ) )[ 0, 1 ] }    #
      split(
        m{\n},
        scalar Cpanel::SafeRun::Errors::saferunnoerror(
            '/usr/bin/systemctl',                                 #
            'show',                                               #
            ( map { ( "-p", $_ ) } @needs_systemd_show_keys ),    #
            $s                                                    #
        )                                                         #
      );
    delete @info{ grep { !length || tr{a-zA-Z0-9_}{}c } keys %info };
    return \%info;
}

sub get_code_and_signal_via_systemd {
    my $p_service = shift;

    my $s = $p_service;
    $s .= '.service' if length($s) < 9 || substr( $s, -8 ) ne '.service';

    my ( $active_state, $exit_code, $exit_signal );

    local $ENV{'LANG'} = 'C';
    local $ENV{'TZ'}   = 'UTC';

    # TODO: change this to use get_service_info_via_systemd which
    # will avoid the parsing of status and be more reliable long term
    # unfortunately the values will be different so all callers will
    # need to be refactored.
    #
    # For example:
    #   $exit_signal being TERM ExecMainStatus would be 15
    #   $exit_code may be ExecMainCode or is it StatusErrno?
    #   The systemd docs are not very clear on this.
    #
    #my $info = get_service_info_via_systemd($p_service);
    #return @{$info}{qw(ActiveState ExecMainCode ExecMainStatus StatusErrno)};

    my @output = Cpanel::SafeRun::Errors::saferunnoerror( '/usr/bin/systemctl', 'status', '--lines=0', $s );
    foreach my $line (@output) {
        last if $line =~ m/^\s*$/;

        #[line][ Main PID: 36359 (code=killed, signal=TERM);         : 36381 (restartsrv_cpsr)]
        #
        if ( $line =~ m{^[ \t]*Active:[ \t]*(\S+)} ) {
            $active_state = $1;
        }
        elsif ( $line =~ m/^[ \t]*Main PID:[ \t]*[0-9]+[ \t]*([^\)]+)/ ) {
            my $state = $1;
            ($exit_code)   = $state =~ m{code=([^, ]+)};
            ($exit_signal) = $state =~ m{signal=([^, ]+)};
        }
    }
    return ( $active_state, $exit_code, $exit_signal );

}

sub get_pids_via_systemd {
    my $p_service = shift;

    my $s = $p_service;
    $s .= '.service' if length($s) < 9 || substr( $s, -8 ) ne '.service';

    local $ENV{'LANG'} = 'C';
    local $ENV{'TZ'}   = 'UTC';
    my @output = Cpanel::SafeRun::Errors::saferunnoerror( '/usr/bin/systemctl', 'status', '--lines=0', $s );
    my $state  = 'SEARCHING';
    my @pids;
    foreach my $line (@output) {
        last if $line =~ m/^\s*$/;
        if ( $state eq 'SEARCHING' ) {

            #    CGroup: /system.slice/dovecot.service
            if ( $line =~ m/^\s*CGroup:/ ) {
                $state = 'COLLECTING';
                next;
            }
            elsif ( $line =~ m/^Loaded: (\w+)/ ) {

                # protect against non-existent units #
                return () if $1 ne 'loaded';
            }
            elsif ( $line =~ m/^Active: (\w+)/ ) {

                # protect against inactive units #
                return () if $1 ne 'active';
            }
        }
        elsif ( $state eq 'COLLECTING' ) {

            #           +-5978 /usr/sbin/dovecot -F -c /etc/dovecot/dovecot.conf
            last if $line !~ m/([0-9]+)\s+/;
            push @pids, $1;
        }
    }

    return @pids;
}

sub has_service_via_systemd {
    my $p_service = shift;

    # if this isn't a systemd service, return false #
    return 0 if !Cpanel::OS::is_systemd();

    # protect against values not being passed in #
    return 0 if !$p_service;

    my $info = get_service_info_via_systemd($p_service);
    return 0 if !defined $info;

    # unknown service
    return 0 if $info->{'LoadState'} eq 'not-found';

    # systemd can manage the service, but this is not a systemd script
    return 0
      if $info->{'FragmentPath'}
      && index( $info->{'FragmentPath'}, '/etc/systemd/system/' ) != 0
      && index( $info->{'FragmentPath'}, '/usr/lib/systemd/' ) != 0
      && index( $info->{'FragmentPath'}, '/lib/systemd/' ) != 0
      && index( $info->{'FragmentPath'}, '/dev/null' ) != 0;

    # Return the info so we don't have to fetch it again
    return $info;
}

sub get_pid_via_systemd {
    my ( $service, $info ) = @_;

    # caller should know, call Cpanel::OS::is_systemd() first #
    _croak('The system is not running systemd.')
      if !Cpanel::OS::is_systemd();

    # systemctl show -p MainPID my.service

    my $s = $service;
    $s .= '.service' if length($s) <= 8 || substr( $s, -8 ) ne '.service';

    {    # try to get MainPID in a light way
        my $output = Cpanel::SafeRun::Errors::saferunnoerror( '/usr/bin/systemctl', 'show', '-p', 'MainPID', $s );
        if ( $? == 0 && $output && $output =~ m{^MainPID=(\d+)$}a ) {
            my $pid = $1;
            return $pid if $pid;    # can be 0 when service is inactive
        }
    }

    $info ||= get_service_info_via_systemd($service);
    return undef if !defined $info;

    # see if it's loaded and running
    # FIXME: should probably return a pid even when the status is inactive...
    if ( $info->{'LoadState'} eq 'loaded' && $info->{'ActiveState'} eq 'active' ) {
        return $info->{'MainPID'} if $info->{'MainPID'};
        if ( $info->{'SubState'} && $info->{'SubState'} eq 'exited' ) {

            # Note: we cannot use --lines here since we need to look though the output
            # since we did not get a MainPID
            my @output = Cpanel::SafeRun::Errors::saferunnoerror( '/usr/bin/systemctl', 'status', $s );
            my ($pid_raw) = grep { !m/^[\w\s]+:/ && m/\d+/ } @output;
            return $1 if $pid_raw =~ m/(\d+)/;
        }
    }

    # If the PIDFile was created outside of systemctl then it is essentially ignored.
    # That means $info indicates its not running, so a later systemctl call can
    # blow the PIDFile away and start a second service running without stopping the first one.
    # To help mitigate that we can check PIDFile at this point:
    if ( $info->{PIDFile} ) {
        require Cpanel::Unix::PID::Tiny;
        return Cpanel::Unix::PID::Tiny->new->is_pidfile_running( $info->{PIDFile} ) || undef;

        # FWiW, the caller checks that the PID it has is still a process of the service in question.
    }

    return undef;
}

sub get_status_via_systemd {
    my $p_service = shift;

    # caller should know, call Cpanel::OS::is_systemd() first #
    _croak('The system is not running systemd.')
      if !Cpanel::OS::is_systemd();

    my $info = get_service_info_via_systemd($p_service);
    return undef if !defined $info;

    # see if it's loaded and running
    return $info->{'ActiveState'} if $info->{'LoadState'} eq 'loaded';
    return undef;
}

sub _run_systemctl {
    return system( '/usr/bin/systemctl', @_ );
}

sub stop_via_systemd {
    my $p_service = shift;

    # caller should know, call Cpanel::OS::is_systemd() first #
    _croak('The system is not running systemd.')
      if !Cpanel::OS::is_systemd();

    my $info = get_service_info_via_systemd($p_service);
    return undef if !defined $info || $info->{'LoadState'} ne 'loaded';

    my $restart_ec = _run_systemctl( 'stop', "${p_service}.service" ) >> 8;
    $info = get_service_info_via_systemd($p_service);
    return $info->{'ActiveState'};
}

sub restart_via_systemd {
    my $p_service = shift;

    # caller should know, call Cpanel::OS::is_systemd() first #
    _croak('The system is not running systemd.')
      if !Cpanel::OS::is_systemd();

    my $info = get_service_info_via_systemd($p_service);
    return ( undef, undef ) if !defined $info || $info->{'LoadState'} ne 'loaded';

    my $restart_ec = _run_systemctl( 'restart', "${p_service}.service" ) >> 8;
    $info = get_service_info_via_systemd($p_service);
    my $status = $info->{'ActiveState'};

    if ($restart_ec) {
        return ( $status, undef );
    }

    return ( $info->{'ActiveState'}, $info->{'MainPID'} );
}
1;
