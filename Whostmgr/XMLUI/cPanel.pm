package Whostmgr::XMLUI::cPanel;

# cpanel - Whostmgr/XMLUI/cPanel.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic(RequireUseWarnings) -- requires fixing for warnings cleanliness

### PAY CAREFUL ATTENTION TO THE DEPS IN THE MODULE ###
### ADDING ANY CAN EASILY INCREASE THE MEMORY USAGE ###
### OF cpsrvd                                       ###
use Socket                       ();
use Cpanel::Encoder::Tiny        ();    # PPI USE OK - used in a regexp
use Cpanel::PwCache              ();
use Cpanel::AcctUtils::Owner     ();
use Cpanel::AccessIds::SetUids   ();
use Cpanel::Reseller             ();
use Cpanel::AdminBin::Serializer ();
use IO::Handle                   ();
### PAY CAREFUL ATTENTION TO THE DEPS IN THE MODULE ###
### ADDING ANY CAN EASILY INCREASE THE MEMORY USAGE ###
### OF cpsrvd                                       ###

sub _format_error {
    my ( $msg, $cfg, $apiversion ) = @_;
    my $error_string = ( ( $apiversion && $apiversion eq '2' ? qq[{"cpanelresult":] : '' ) . qq[{"data":{"reason":"__ERROR__","result":"0"},"type":"text","error":"__ERROR__"}\n] . ( $apiversion && $apiversion eq '2' ? '}' : '' ) );
    $error_string =~ s/__ERROR__/Cpanel::Encoder::Tiny::safe_html_encode_str( $msg )/eg;
    return $error_string;
}

sub cpanel_exec {
    my ( $OPTSref, $socket, $has_root, $cfg ) = @_;
    my $user = $OPTSref->{'cpanel_jsonapi_user'};
    if ( !defined $user && $OPTSref->{'user'} ) {
        $user = $OPTSref->{'user'};
        delete $OPTSref->{'user'};
    }

    my ( $output, $internal_error, $internal_error_reason );

    my @pw = Cpanel::PwCache::getpwnam($user);
    if ( $pw[0] eq '' ) {
        $output = _format_error( 'User parameter is invalid or was not supplied', $cfg, $OPTSref->{'cpanel_jsonapi_apiversion'} );
        return wantarray ? ( length($output), \$output ) : $output;
    }
    elsif ( $pw[2] == 0 ) {    # root
        $output = _format_error( "The user “$pw[0]” is not associated with a cPanel account and cannot call cPanel API 2", $cfg, $OPTSref->{'cpanel_jsonapi_apiversion'} );
        return wantarray ? ( length($output), \$output ) : $output;
    }

    if ( !defined $has_root ) {
        eval 'use Whostmgr::ACLS (); $has_root = Whostmgr::ACLS::hasroot();';    ## no critic(ProhibitStringyEval)
    }
    if ( $has_root || $user eq $ENV{'REMOTE_USER'} || $ENV{'REMOTE_USER'} eq Cpanel::AcctUtils::Owner::getowner($user) ) {
        my $read_pipe  = IO::Handle->new();
        my $write_pipe = IO::Handle->new();
        socketpair( $read_pipe, $write_pipe, Socket::AF_UNIX(), Socket::SOCK_STREAM(), Socket::PF_UNSPEC() );
        $read_pipe->autoflush(1);
        $write_pipe->autoflush(1);

        if ( my $pid = open( my $output_fh, '-|' ) ) {
            Cpanel::AdminBin::Serializer::DumpFile( $write_pipe, {%$OPTSref} );
            local $/;
            close($write_pipe);
            $output = readline($output_fh);
            if ( !length $output ) {
                $internal_error_reason = 'No data returned from cPanel Service';
                $output                = _format_error( $internal_error_reason, $cfg, $OPTSref->{'cpanel_jsonapi_apiversion'} );
                $internal_error        = 1;
            }

            # waitpid ($pid, 0); # perldoc -f open: "Closing any piped filehandle causes the parent process to wait for the child to finish, and returns the status value in $?."
        }
        elsif ( defined $pid ) {
            Cpanel::AccessIds::SetUids::setuids($user) || die "Could not setuid to $user";

            # TODO: find some way better than environment variables to pass this
            #       information to cpanel
            if ( Cpanel::Reseller::isreseller( $ENV{'REMOTE_USER'} ) ) {
                $ENV{'CPRESELLER'} = $ENV{'REMOTE_USER'};
            }

            $ENV{'REMOTE_USER'} = $user;
            my $sendxml    = IO::Handle->new();
            my $cpanel_bin = get_cpanel_bin();
            my $mode       = '--json-fast-connect';
            open( STDIN, '<&=' . fileno($read_pipe) ) or exit 1;    ## no critic (ProhibitTwoArgOpen);
            exec $cpanel_bin, $mode, '--stdin' or exit 1;
        }
        else {
            $output = _format_error( "fork() failed: $!", $cfg, ( $OPTSref->{'cpanel_jsonapi_apiversion'} ) );
        }
    }
    else {
        $output = _format_error( "Access Denied to $user", $cfg, ( $OPTSref->{'cpanel_jsonapi_apiversion'} ) );
    }
    return wantarray ? ( length($output), \$output, $internal_error, $internal_error_reason ) : $output;
}

sub get_cpanel_bin {
    my $cpanel_bin = '/usr/local/cpanel/cpanel';
    if ( -x $cpanel_bin . '.pl' && !-e $cpanel_bin ) {
        $cpanel_bin .= '.pl';
    }
    return $cpanel_bin;
}

1;
