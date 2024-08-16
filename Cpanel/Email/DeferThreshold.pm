package Cpanel::Email::DeferThreshold;

# cpanel - Cpanel/Email/DeferThreshold.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

# Minimum number of failures in an hour after which we will defer the ability to
# stop outgoing email.

use strict;
use constant DEFAULT_DEFER_THRESHOLD => 5;

our $cached_defer_threshold;

sub defer_threshold {
    if ( !defined($cached_defer_threshold) || !length($cached_defer_threshold) ) {
        require Cpanel::Config::LoadCpConf;
        my $conf = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();
        $cached_defer_threshold = $conf->{email_send_limits_min_defer_fail_to_trigger_protection};
        $cached_defer_threshold = DEFAULT_DEFER_THRESHOLD() if !defined($cached_defer_threshold) || !length($cached_defer_threshold);
    }
    return $cached_defer_threshold;
}

1;

__END__

=pod

=head1 min_defer_fail_to_trigger_protection

  This is essentially a minimum required sample size before considering
  the deferred/failed percentage, except it is a minimum for the number of
  defers/fails rather than the total number of emails.

  Assuming the max defer/fail percentage is set to 55% and the
  min defer/fail to trigger protection is set to 7 emails, consider
  the following table:

  Defer/fail | Success | Pct def/fail | Status
    1             0       100%            OK (pct is high, but min defer/fail not met yet)
    2             0       100%            OK ...
    2             1       67%             OK ...
    2             2       50%             OK ...
    3             2       60%             OK ...
    4             2       67%             OK ...
    5             2       71%             OK ...
    6             2       75%             OK ...
    6             3       67%             OK ...
    6             4       60%             OK ...
    6             5       55%             OK ...
    6             6       50%             OK (neither condition is met)
    6             7       46%             OK (neither condition is met)
    7             7       50%             OK (min defer/fail met, but pct is below 55%)
    8             7       53%             OK ...
    9             7       56%             NOT OK (min defer/fail met, and pct beyond 55%)

  On the other hand, if there are no successes within the same period, the
  protection will kick in much sooner:

  Defer/fail | Success | Pct def/fail | Status
    1             0       100%            OK (pct is high, but min defer/fail not met yet)
    2             0       100%            OK ...
    3             0       100%            OK ...
    4             0       100%            OK ...
    5             0       100%            OK ...
    6             0       100%            OK ...
    7             0       100%            NOT OK

=cut
