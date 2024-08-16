package Cpanel::EmailTracker::Purge;

# cpanel - Cpanel/EmailTracker/Purge.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=pod

=encoding utf-8

=head1 NAME

Cpanel::EmailTracker::Purge - clean up email tracking files used by exim

=head1 FUNCTIONS

=head2 purge_old_tracker_files_by_domain( DOMAIN, PURGE_TIME, NOW )

Purge away email tracking files for a given domain. PURGE_TIME defaults to one
day, NOW to the system time. Includes removing max_emails_per_day throttle
touchfile.

=cut

sub purge_old_tracker_files_by_domain {
    my $domain     = shift;
    my $purge_time = shift || time() - 86400;    #default to a day ago
    my $now        = shift || time();

    if ( opendir( my $domain_track_fh, '/var/cpanel/email_send_limits/track/' . $domain ) ) {
        my $has_files = 0;
        while ( my $domaintime = readdir($domain_track_fh) ) {
            next if ( $domaintime =~ /^\.\.?$/ );
            my $tracker_file_mtime = ( lstat("/var/cpanel/email_send_limits/track/$domain/$domaintime") )[9];
            if ( $tracker_file_mtime < $purge_time || $tracker_file_mtime > $now ) {
                unlink("/var/cpanel/email_send_limits/track/$domain/$domaintime");
            }
            else {
                $has_files++;
            }
        }
        if ( !$has_files ) { rmdir( '/var/cpanel/email_send_limits/track/' . $domain ); }
    }
    if ( -e "/var/cpanel/email_send_limits/daily_notify/$domain" ) {
        my $tracker_file_mtime = ( lstat("/var/cpanel/email_send_limits/daily_notify/$domain") )[9];
        if ( $tracker_file_mtime < $purge_time || $tracker_file_mtime > $now ) {
            unlink("/var/cpanel/email_send_limits/daily_notify/$domain");
            unlink( '/var/cpanel/email_send_limits/daily_notify/' . $domain . '_send' );
        }
    }
    return;
}

=head2 purge_old_tracker_files

For all domains currently being tracked, hunt down and remove old tracking files.

=cut

sub purge_old_tracker_files {
    my $now;
    my $purge_time = shift || ( $now ||= time() ) - 86400;    #default to a day ago
    if ( opendir( my $track_fh, '/var/cpanel/email_send_limits/track' ) ) {
        while ( my $domain = readdir($track_fh) ) {
            next if ( $domain =~ /^\.\.?$/ );
            purge_old_tracker_files_by_domain( $domain, $purge_time, ( $now ||= time() ) );
            purge_old_notification_throttle($domain);
        }
    }
    return;
}

=head2 purge_old_nofication_throttle( DOMAIN )

Remove notifications throttle for max_emails_per_hour, if one hour or more has passed.

=cut

sub purge_old_notification_throttle {
    my $domain     = shift;
    my $purge_time = time() - 3600;    # one hour
    my $now        = time();
    if ( -e "/var/cpanel/email_send_limits/hourly_notify/$domain" ) {
        my $tracker_file_mtime = ( lstat("/var/cpanel/email_send_limits/hourly_notify/$domain") )[9];
        if ( $tracker_file_mtime < $purge_time || $tracker_file_mtime > $now ) {
            unlink("/var/cpanel/email_send_limits/hourly_notify/$domain");
        }
    }
    return;
}

1;
