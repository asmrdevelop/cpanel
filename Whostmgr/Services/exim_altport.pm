package Whostmgr::Services::exim_altport;

# cpanel - Whostmgr/Services/exim_altport.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Whostmgr::UI      ();
use Cpanel::ArrayFunc ();

=head1 NAME

Whostmgr::Services::exim_altport

=head1 SYNOPSIS

    use Whostmgr::Services     ();
    use Whostmgr::Exim::Config ();

    Cpanel::LoadModule::load_perl_module('Whostmgr::Services::exim_altport');

    my $formref = { 'exim-altport' => 1, 'exim-altportmonitor' => 1 };\
    my %MONITORED;
    my %UNMONITORED

    my ($configured_ok, $msg, $need_to_rebuild_exim_conf) = Whostmgr::Services::exim_altport::configure( $formref, \%MONITORED, \%UNMONITORED);

    if( $configured_ok && $need_to_rebuild_exim_conf ) {
        Whostmgr::Exim::Config::attempt_exim_config_update()
        Whostmgr::Services::add_services_to_restart('exim');
    }


=head1 DESCRIPTION

C<Whostmgr::Services::exim_altport> is a modularization of custom exim-altport code formerly found in whostmgr/bin/whostmgr.pl.
Specifically, it takes logic from the 'dosrvmng' function.
This has been done so as to enable WHMAPI1 to actually be able to configure this service as well.
See CPANEL-13089 for more details.

=cut

=head2 B<configure ()>

Does all the things to actually setup exim on an alternate port other than updating configs and restarting it..
See SYNOPSIS for an example use case.

B<Input>

    HASHREF
        exim-altport        - BOOLEAN Whether to enable/disable the service. Defaults to false (disable)
        exim-altportmonitor - BOOLEAN Whether to enable/disable monitoring for the service. Defaults to false (disable)
        exim-altportnum     - STRING Comma-separated list of ports to use

    HASHREF
        returns a hash of the ports in the form exim-## that should be enabled for monitoring, if you're going to do that.

    HASHREF
        returns a hash of the ports in the form exim-## that should be *disabled* for monitoring.

=cut

# localize these, for testing

our $CHKSERV_DIRECTORY     = '/etc/chkserv.d';
our $CHKSERV_VAR_DIRECTORY = 'var/run/chkservd';

# XXX NOTE we're passing around references here without returning them. Expect some 'spooky action at a distance'.
sub configure {
    my ( $formref, $MONITORED, $UNMONITORED ) = @_;

    # Exim Alternate Port Code
    my $current_exim_altport = get_current_exim_altport() || q{};
    my $exim_altport_enabled = $current_exim_altport ne q{};

    # Avoid unint value warns
    $formref->{'exim-altport'}        //= '';
    $formref->{'exim-altportmonitor'} //= '';
    $formref->{'exim-altportnum'}     //= '';

    my $rebuild_eximconf = 0;

    my @requested_ports = split( m/[\s\,]+/, $formref->{'exim-altportnum'} =~ /([\,\s0-9]+)/ ? $1 : 26 );

    if ( my $invalid_port = Cpanel::ArrayFunc::first( sub { $_ == 25 || $_ == 465 || $_ == 587 }, @requested_ports ) ) {
        my $error_string = "Unable to set exim altport to $invalid_port. Please select another port.";
        print Whostmgr::UI::setstatus($error_string);
        print Whostmgr::UI::setstatuserror();
        return ( 0, $error_string, $rebuild_eximconf );
    }

    my $exim_altport_number = join( ',', grep { $_ > 0 && $_ < 65535 } sort { $a <=> $b } @requested_ports );

    # safe default since they did not pass a numeric port
    # otherwise you'd get '/usr/sbin/exim -oX  -bd' (note extra space between -oX and -bd from the null var) instead of '/usr/sbin/exim -oX 26 -bd'

    if ( $formref->{'exim-altport'} eq '1' && $current_exim_altport ne $exim_altport_number ) {
        if ($current_exim_altport) {
            unlink( "$CHKSERV_DIRECTORY/exim-" . $current_exim_altport );
            delete $MONITORED->{ 'exim-' . $current_exim_altport };
            unlink "$CHKSERV_VAR_DIRECTORY/exim-" . $current_exim_altport;
            $UNMONITORED->{ 'exim-' . $current_exim_altport } = 1;
        }

        # We only need to check one port
        my $first_exim_altport_number = ( split( /\,/, $exim_altport_number ) )[0];

        open( my $EXIMALT, '>', "$CHKSERV_DIRECTORY/exim-$exim_altport_number" ) || die "Could not open $CHKSERV_DIRECTORY\/exim-$exim_altport_number";
        print $EXIMALT "service[exim-$exim_altport_number]=$first_exim_altport_number,QUIT,220,/usr/local/cpanel/scripts/restartsrv_exim\n";
        close($EXIMALT);
        $rebuild_eximconf = 1;
    }
    elsif ( !$formref->{'exim-altport'} && $exim_altport_enabled == 1 ) {
        unlink( "$CHKSERV_DIRECTORY/exim-" . $current_exim_altport );
        delete $MONITORED->{ 'exim-' . $current_exim_altport };
        unlink "$CHKSERV_VAR_DIRECTORY/exim-" . $current_exim_altport;
        $UNMONITORED->{ 'exim-' . $current_exim_altport } = 1;
        $rebuild_eximconf = 1;
    }
    print Whostmgr::UI::setstatus( qq{Saving Changes to exim-$exim_altport_number } . ( $formref->{'exim-altport'} ? q{(enabled)} : q{(disabled)} ) );
    print Whostmgr::UI::setstatusdone();
    if ( $formref->{'exim-altportmonitor'} ne '1' ) {
        delete $MONITORED->{ 'exim-' . $exim_altport_number };
        delete $MONITORED->{ 'exim-' . $current_exim_altport };
        unlink "$CHKSERV_VAR_DIRECTORY/exim-" . $exim_altport_number;
        unlink "$CHKSERV_VAR_DIRECTORY/exim-" . $current_exim_altport;
        $UNMONITORED->{ 'exim-' . $exim_altport_number } = 1;
        if ($current_exim_altport) {
            $UNMONITORED->{ 'exim-' . $current_exim_altport } = 1;
        }
    }
    elsif ( $formref->{'exim-altport'} ) {
        $MONITORED->{ 'exim-' . $exim_altport_number } = 1;
        delete $UNMONITORED->{ 'exim-' . $exim_altport_number };
    }
    return ( 1, 'OK', $rebuild_eximconf );
}

sub get_current_exim_altport {

    require Cpanel::FileUtils::Dir;
    my $nodes = Cpanel::FileUtils::Dir::get_directory_nodes_if_exists($CHKSERV_DIRECTORY);

    if ($nodes) {
        for (@$nodes) {
            return substr( $_, 5 ) if index( $_, "exim-" ) == 0;
        }
    }

    return;
}

1;
