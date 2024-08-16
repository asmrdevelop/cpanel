package Whostmgr::Remote::Parser;

# cpanel - Whostmgr/Remote/Parser.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Exception ();
use Cpanel::Locale::Lazy ('lh');
use Whostmgr::Remote::State ();

use parent 'Cpanel::Parser::Base';

our $BEFORE_SSHCONTROL_OUTPUT = 0;
our $IN_SSHCONTROL_OUTPUT     = 1;
our $AFTER_SSHCONTROL_OUTPUT  = 2;

sub new {
    my ( $class, %OPTS ) = @_;

    my $self = {
        'escalation_method_used' => undef,
        'ctl_pid'                => undef,
        'ctl_path'               => undef,
        'data_terminator'        => undef,
        #
        #
        '_indata' => $BEFORE_SSHCONTROL_OUTPUT,
        '_buffer' => '',
    };

    $self->{'output_callback'} = $OPTS{'output_callback'} if $OPTS{'output_callback'};
    $self->{'print'}           = $OPTS{'print'};
    $self->{'timeout'}         = $OPTS{'timeout'};

    bless $self, $class;

    $self->init(%OPTS) if $self->can('init');

    return $self;
}

sub process_error_line {
    my ( $self, $line ) = @_;

    # As of v56 we only allocate a tty when we need one
    # so we need to supress this spurious error
    return 1 if $line =~ m{^stdin: is not a tty\r?\n?$};

    return print $Whostmgr::Remote::State::ERROR_PREFIX . $line;
}

sub process_line {
    my ( $self, $line ) = @_;

    if ( $self->{'_indata'} != $IN_SSHCONTROL_OUTPUT ) {
        $self->{'raw'} .= $line;

        if ( $line =~ m{^==sshcontrolescalation_method=([^=\n]+)} ) {
            $self->{'escalation_method_used'} = $1;
        }
        elsif ( $line =~ m{^==sshcontrolpid=([^=\n]+)} ) {
            $self->{'ctl_pid'} = $1;
        }
        elsif ( $line =~ m{^==sshcontrolpath=([^=\n]+)} ) {
            $self->{'ctl_path'} = $1;
        }
        elsif ( $line =~ m{^==sshcontrol_error} ) {
            $line =~ m{^==sshcontrol_error=([^=]+)=([^=]*)=};
            my $key       = $1;
            my $raw_error = $2;

            if ( !$key || !__PACKAGE__->can("_ERRSTR_$key") ) {
                $key = 'RemoteSSHAccessDenied';
            }

            $raw_error =~ s/[\r\n]*$// if $raw_error;

            my $errstr = __PACKAGE__->can("_ERRSTR_$key")->(
                $Whostmgr::Remote::State::last_active_host,
                $raw_error || q<>,
            );

            die Cpanel::Exception::create_raw( $key, $errstr );
        }
        elsif ( $line =~ /==sshcontroloutput==([^=]+)==/ ) {
            $self->{'data_terminator'} = $1;
            $self->{'_indata'}         = $IN_SSHCONTROL_OUTPUT;
        }

        $self->_parse_nondata_line($line);
    }
    else {    # $IN_SSHCONTROL_OUTPUT
        if ( $line =~ /==sshcontroloutput==\Q$self->{'data_terminator'}\E==/ ) {
            my ($raw) = $line =~ m/(==sshcontroloutput==\Q$self->{'data_terminator'}\E==\r*\n?)$/;
            if ( length $raw ) {
                $line =~ s/==sshcontroloutput==\Q$self->{'data_terminator'}\E==\r*\n?$//;
                $self->{'raw'} .= $raw;
            }
            $self->{'_indata'} = $AFTER_SSHCONTROL_OUTPUT;
            return 1 unless length $line;
        }

        $self->{'output_callback'}->($line) if $self->{'output_callback'};

        $self->_parse_data_line($line);
    }

    return 1;
}

sub ctl_pid {
    my ($self) = @_;
    return $self->{'ctl_pid'};
}

sub ctl_path {
    my ($self) = @_;
    return $self->{'ctl_path'};
}

sub escalation_method_used {
    my ($self) = @_;
    return $self->{'escalation_method_used'};
}

sub error {
    my ($self) = @_;
    return $self->{'error'};
}

sub raw {
    my ($self) = @_;
    return $self->{'raw'};
}

sub raw_error {
    my ($self) = @_;
    return $self->{'raw_error'};
}

sub result {
    my ($self) = @_;
    return $self->{'result'};
}

#----------------------------------------------------------------------

sub _ERRSTR_RemoteSSHHostNotFound {
    my ( $host, $raw_error ) = @_;
    return lh()->maketext( "The IP address or hostname that you provided ([_1]) is not valid: [_2]", $host, $raw_error );
}

sub _ERRSTR_RemoteSSHAccessDenied {
    my ( $host, $raw_error ) = @_;
    return lh()->maketext( "The password that you provided is not correct, or the [asis,SSH] key is not permitted access: [_1]", $raw_error );
}

sub _ERRSTR_RemoteSSHConnectionFailed {
    my ( $host, $raw_error ) = @_;
    return lh()->maketext( "The remote server “[_1]” unexpectedly terminated the connection. The port may be incorrect, or the remote server may not allow connections from this server: [_2]", $host, $raw_error );
}

sub _ERRSTR_RemoteSSHTimeout {
    my ( $host, $raw_error ) = @_;
    return lh()->maketext( "The system experienced a timeout error while it attempted to connect to “[_1]”: [_2]", $host, $raw_error );
}

sub _ERRSTR_RemoteSSHRootEscalationFailed {
    my ( $host, $raw_error ) = @_;
    return lh()->maketext( "The system failed to escalate privileges to root on “[_1]” with “[_2]” or “[_3]” because of an error: [_4]", $host, 'sudo', 'su', $raw_error );
}

sub _ERRSTR_RemoteSSHMissing {
    my ( $host, $raw_error ) = @_;
    return lh()->maketext( "Critical SSH or support files appear to be missing: [_1]", $raw_error );
}

sub _ERRSTR_RemoteSCPMissing {
    my ( $host, $raw_error ) = @_;
    return lh()->maketext( "The “[_1]” command is disabled or missing on the remote server “[_2]”: [_3]", 'scp', $host, $raw_error );
}

sub _ERRSTR_RemoteSCPError {
    my ( $host, $raw_error ) = @_;
    return lh()->maketext( "The “[_1]” command failed because of an error: [_2]", $host, $raw_error );
}

sub _parse_nondata_line {
    return 1;
}

sub _parse_data_line {
    my ( $self, $line ) = @_;

    $self->{'result'} .= $line;
    print $line if $self->{'print'};

    return 1;
}

1;
