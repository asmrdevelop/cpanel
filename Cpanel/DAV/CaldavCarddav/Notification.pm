
# cpanel - Cpanel/DAV/CaldavCarddav/Notification.pm
#                                                  Copyright 2024 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
package Cpanel::DAV::CaldavCarddav::Notification;

use strict;
use warnings;
use Cpanel::AccessIds::ReducedPrivileges ();
use Cpanel::Config::Users                ();
use Cpanel::Notify                       ();
use Cpanel::Pkgr                         ();
use Cpanel::PwCache                      ();
use Cpanel::ServerTasks                  ();

=head1 NAME

Cpanel::DAV::CaldavCarddav::Notification

=head1 FUNCTIONS

=head2 queue_reconfigure_calendars_notification

=cut

sub queue_reconfigure_calendars_notification {
    my ($send) = @_;
    return if !$send;

    if ( migration_done() ) {
        return Cpanel::ServerTasks::queue_task( ['EmailTasks'], 'reconfigure_calendars_notification' );
    }

    return Cpanel::ServerTasks::schedule_task( ['EmailTasks'], 3600 * 3, 'reconfigure_calendars_notification' );
}

=head2 reconfigure_calendars_notification

This notification is related to the transition from CCS to cpdavd (Feature Showcase
item reconfigure_calendars.json). It can be removed at the same time that Feature
Showcase item is removed.

=cut

sub reconfigure_calendars_notification {
    my $users_to_notify = _users_with_calendar_data();
    my @notified;

    for my $sys_user ( sort keys %$users_to_notify ) {
        for my $dav_user ( @{ $users_to_notify->{$sys_user} } ) {

            Cpanel::Notify::notification_class(
                class            => 'Mail::ReconfigureCalendars',
                application      => 'Mail::ReconfigureCalendars',
                constructor_args => [
                    username                          => $sys_user,
                    to                                => $dav_user,
                    account                           => $dav_user,
                    source_ip_address                 => '127.0.0.1',    # No reason to disclose the IP address of the person who clicked through the Feature Showcase
                    origin                            => 'whm',
                    notification_targets_user_account => 1,
                    notification_cannot_be_disabled   => 1,
                ]
            );
            push @notified, {
                sys_user => $sys_user,
                dav_user => $dav_user,
            };
        }
    }

    return \@notified;
}

# Returns a structure like this:
# {
#     'sysuser' => [
#         'sysuser',              # The cPanel user itself has calendar/contact data
#         'somebody@sysuser.tld', # An email account has calendar/contact data
#         ...
#     ],
#     ...
# }
sub _users_with_calendar_data {

    my $sys_users_ar = Cpanel::Config::Users::getcpusers();
    my %has_data;

    if ( migration_done() ) {
        for my $sys_user (@$sys_users_ar) {
            my $homedir = Cpanel::PwCache::gethomedir($sys_user) or do {
                warn "Couldn't find home directory for $sys_user";
                next;
            };

            Cpanel::AccessIds::ReducedPrivileges::call_as_user(
                $sys_user,
                sub {
                    opendir my $caldav_dh, "$homedir/.caldav" or return;
                    my %dav_users = map { /\w/ ? ( $_ => "$homedir/.caldav/$_" ) : () } readdir $caldav_dh;
                    closedir $caldav_dh;
                  DAV_USER: for my $name ( sort keys %dav_users ) {
                        my $dir = $dav_users{$name};

                        for ( [ 'calendar', 'ics' ], [ 'addressbook', 'vcf' ] ) {
                            my ( $subdir, $extension ) = @$_;

                            opendir my $subdir_dh, "$dir/$subdir" or next;
                            while ( my $thing = readdir $subdir_dh ) {
                                if ( $thing =~ /\.\Q$extension\E$/ ) {
                                    $has_data{$sys_user} //= [];
                                    push @{ $has_data{$sys_user} }, $name;
                                    next DAV_USER;
                                }
                            }
                            closedir $subdir_dh;
                        }
                    }
                },
            );
        }
    }
    else {
        warn "Migration is still not done. Unable to determine correct list of users to notify.\n";    # If it's still not done at this point, it also might have failed somehow
    }

    return \%has_data;
}

=head2 had_or_have_ccs()

Returrns true if the server either previously had CCS and has already finished the conversion or
still has it installed. This is used for checking whether the feature showcase item about notifying
end-users to reconfigure clients should be shown.

=cut

sub had_or_have_ccs {
    my $installed = Cpanel::Pkgr::installed_packages('cpanel-ccs-calendarserver');
    return !!( $installed->{'cpanel-ccs-calendarserver'} || migration_done() );
}

=head2 migration_done()

Returns true if the migration from CCS to cpdavd has finished.

=cut

sub migration_done {
    return -e '/var/cpanel/migrate_ccs_to_cpdavd.done';
}

1;
