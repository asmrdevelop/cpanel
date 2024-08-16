package Cpanel::EximStats::Retention;

# cpanel - Cpanel/EximStats/Retention.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

our $VERSION                     = 1.0;
our $DEFAULT_EXIM_RETENTION_DAYS = 90;

sub get_valid_exim_retention_days {
    my ( $days, $cpconf ) = @_;

    unless ( exim_retention_days_ok($days) ) {
        if ( !$cpconf ) {
            require Cpanel::Config::LoadCpConf;
            $cpconf = Cpanel::Config::LoadCpConf::loadcpconf();
        }
        $days = $cpconf->{'exim_retention_days'};
    }

    unless ( exim_retention_days_ok($days) ) {
        $days = $DEFAULT_EXIM_RETENTION_DAYS;
    }
    return $days;
}

sub exim_retention_days_ok {
    my $days = shift;
    return defined $days && $days =~ / ^ (?:[-+])? \d+ (?:[.]\d+)? $ /x && $days >= 0;
}

1;
