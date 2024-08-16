package Whostmgr::Exim::Sysconfig;

# cpanel - Whostmgr/Exim/Sysconfig.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=pod

=encoding utf-8

=head1 NAME

Whostmgr::Exim::Sysconfig - Update values in /etc/sysconfig/exim which WHM manages

=head1 SYNOPSIS

    use Whostmgr::Exim::Sysconfig  ();
    use Cpanel::Config::LoadCpConf ();

    my $cp_config = scalar Cpanel::Config::LoadCpConf::loadcpconf();
    Whostmgr::Exim::Sysconfig::update_sysconfig( $cp_config->{'exim-retrytime'} );

=head1 FUNCTIONS

=cut

use cPstrict;

sub _etc_sysconfig_exim { return '/etc/sysconfig/exim' }

=head2 update_sysconfig( $queue_time_in_minutes )

Read in the contents of /etc/sysconfig/exim, change the value of the QUEUE
variable, add the DAEMON variable if it does not exist, and write the
altered contents back out to /etc/sysconfig/exim.

=cut

sub update_sysconfig ($val) {
    my $sysconf = '';
    my $hasd    = 0;
    my $hasq    = 0;

    if ( -e _etc_sysconfig_exim() && open my $fh, '<', _etc_sysconfig_exim() ) {

        while (<$fh>) {
            if (/^QUEUE=/) {
                $hasq = 1;
                $sysconf .= "QUEUE=${val}m\n";
                next;
            }
            if (/^DAEMON=/) {
                $hasd = 1;
            }
            $sysconf .= $_;
        }
        close $fh;
    }

    $sysconf .= "QUEUE=${val}m\n" if !$hasq;
    $sysconf .= "DAEMON=yes\n"    if !$hasd;

    if ( open my $fh, '>', _etc_sysconfig_exim() ) {
        print {$fh} $sysconf;
        close $fh;
    }

    return;
}

1;
